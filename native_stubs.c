// native_stubs.c: POSIX helpers for the `mb` tool.
//
// Only Linux and macOS are supported. Everything here is small and
// dependency-free so the package links against plain libc.

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#include "moonbit.h"

// Run `cmd` through the shell, inheriting stdio. Returns the process exit
// code (128 + signal number when killed by a signal, -1 on fork failure).
MOONBIT_FFI_EXPORT int mb_system(moonbit_bytes_t cmd) {
  int status = system((const char *)cmd);
  if (status == -1) {
    return -1;
  }
  if (WIFEXITED(status)) {
    return WEXITSTATUS(status);
  }
  if (WIFSIGNALED(status)) {
    return 128 + WTERMSIG(status);
  }
  return status;
}

// Run `cmd` through the shell, capturing stdout+stderr.
MOONBIT_FFI_EXPORT moonbit_bytes_t mb_popen(moonbit_bytes_t cmd) {
  FILE *fp = popen((const char *)cmd, "r");
  if (fp == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  size_t cap = 8192, len = 0;
  char *buf = (char *)malloc(cap);
  if (buf == NULL) {
    pclose(fp);
    return moonbit_make_bytes(0, 0);
  }
  for (;;) {
    if (len + 1 >= cap) {
      cap *= 2;
      char *grown = (char *)realloc(buf, cap);
      if (grown == NULL) {
        free(buf);
        pclose(fp);
        return moonbit_make_bytes(0, 0);
      }
      buf = grown;
    }
    size_t n = fread(buf + len, 1, cap - len - 1, fp);
    if (n == 0) {
      break;
    }
    len += n;
  }
  buf[len] = '\0';
  pclose(fp);
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  memcpy(out, buf, len);
  free(buf);
  return out;
}

// Platform triple used to pick the MoonBit toolchain archive.
MOONBIT_FFI_EXPORT moonbit_bytes_t mb_platform(void) {
  const char *p;
#if defined(__APPLE__)
#if defined(__aarch64__) || defined(__arm64__)
  p = "darwin-aarch64";
#else
  p = "darwin-x86_64";
#endif
#elif defined(__linux__)
#if defined(__aarch64__)
  p = "linux-aarch64";
#else
  p = "linux-x86_64";
#endif
#else
  p = "";
#endif
  size_t len = strlen(p);
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  memcpy(out, p, len);
  return out;
}

// chmod a file to 0755. Returns 0 on success.
MOONBIT_FFI_EXPORT int mb_chmod_exec(moonbit_bytes_t path) {
  return chmod((const char *)path, 0755);
}

// Read one line from stdin, without the trailing newline. Returns an empty
// string on EOF.
MOONBIT_FFI_EXPORT moonbit_bytes_t mb_read_line(void) {
  size_t cap = 128, len = 0;
  char *buf = (char *)malloc(cap);
  if (buf == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  int c;
  while ((c = fgetc(stdin)) != EOF && c != '\n') {
    if (len + 1 >= cap) {
      cap *= 2;
      char *grown = (char *)realloc(buf, cap);
      if (grown == NULL) {
        free(buf);
        return moonbit_make_bytes(0, 0);
      }
      buf = grown;
    }
    buf[len++] = (char)c;
  }
  if (len > 0 && buf[len - 1] == '\r') {
    len--;
  }
  moonbit_bytes_t out = moonbit_make_bytes((int32_t)len, 0);
  memcpy(out, buf, len);
  free(buf);
  return out;
}

// Whether stdout is a terminal (used for colour/progress decisions).
MOONBIT_FFI_EXPORT int mb_isatty_stdout(void) {
  return isatty(STDOUT_FILENO) ? 1 : 0;
}

// Terminate the process with `code`.
MOONBIT_FFI_EXPORT void mb_exit(int code) {
  exit(code);
}

// Whether stdin is a terminal.
MOONBIT_FFI_EXPORT int mb_isatty_stdin(void) {
  return isatty(STDIN_FILENO) ? 1 : 0;
}

// Write bytes to stdout without a trailing newline. Returns bytes written.
MOONBIT_FFI_EXPORT int mb_write(moonbit_bytes_t data) {
  size_t len = (size_t)Moonbit_array_length(data);
  if (len == 0) {
    return 0;
  }
  fwrite(data, 1, len, stdout);
  fflush(stdout);
  return (int)len;
}

static struct termios mb_saved_termios;
static int mb_raw_active = 0;

// Put stdin into non-canonical, no-echo mode so a prompt can read single
// keypresses. Returns 0 on success.
MOONBIT_FFI_EXPORT int mb_tty_raw(void) {
  if (mb_raw_active) {
    return 0;
  }
  if (!isatty(STDIN_FILENO)) {
    return -1;
  }
  if (tcgetattr(STDIN_FILENO, &mb_saved_termios) != 0) {
    return -1;
  }
  struct termios raw = mb_saved_termios;
  raw.c_lflag &= ~(ICANON | ECHO);
  raw.c_cc[VMIN] = 1;
  raw.c_cc[VTIME] = 0;
  if (tcsetattr(STDIN_FILENO, TCSANOW, &raw) != 0) {
    return -1;
  }
  mb_raw_active = 1;
  return 0;
}

// Undo mb_tty_raw.
MOONBIT_FFI_EXPORT int mb_tty_restore(void) {
  if (!mb_raw_active) {
    return 0;
  }
  int rc = tcsetattr(STDIN_FILENO, TCSANOW, &mb_saved_termios);
  mb_raw_active = 0;
  return rc;
}

// Read one byte from stdin. With timeout_ms > 0, wait at most that long.
// Returns the byte (0..255), or -1 on timeout or EOF.
MOONBIT_FFI_EXPORT int mb_read_byte(int timeout_ms) {
  if (timeout_ms > 0) {
    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(STDIN_FILENO, &fds);
    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    int ready = select(STDIN_FILENO + 1, &fds, NULL, NULL, &tv);
    if (ready <= 0) {
      return -1;
    }
  }
  unsigned char c;
  ssize_t n = read(STDIN_FILENO, &c, 1);
  if (n <= 0) {
    return -1;
  }
  return (int)c;
}
