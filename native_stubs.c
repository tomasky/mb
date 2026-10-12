// native_stubs.c: POSIX helpers for the `mb` tool.
//
// Only Linux and macOS are supported. Everything here is small and
// dependency-free so the package links against plain libc.

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
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

// Whether stdout is a terminal (used for colour/progress decisions).
MOONBIT_FFI_EXPORT int mb_isatty_stdout(void) {
  return isatty(STDOUT_FILENO) ? 1 : 0;
}

// Terminate the process with `code`.
MOONBIT_FFI_EXPORT void mb_exit(int code) {
  exit(code);
}
