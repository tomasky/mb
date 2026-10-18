///|
/// Small utilities: paths, filesystem helpers, process spawning and hashing.
/// Everything here is written against libc via `native_stubs.mbt` and
/// `moonbitlang/x`.

///|
/// Read an environment variable, returning `default` when unset or empty.
pub fn env_or(name : String, default : String) -> String {
  match @env.get_env_var(name) {
    Some(v) => if v == "" { default } else { v }
    None => default
  }
}

///|
pub fn path_join(a : String, b : String) -> String {
  if a == "" {
    b
  } else if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
/// Join any number of path segments with `/`.
pub fn path_join_all(parts : Array[String]) -> String {
  let mut out = ""
  for p in parts {
    out = path_join(out, p)
  }
  out
}

///|
pub fn home_dir() -> String raise MbError {
  let home = env_or("HOME", "")
  if home == "" {
    raise MbError("HOME is not set; cannot determine the user home directory")
  } else {
    home
  }
}

///|
/// Root of `mb`'s own data directory (installed toolchains and tools).
///
/// Resolution order: `MB_HOME`, then `$XDG_DATA_HOME/mb`, then
/// `~/.local/share/mb`.
pub fn mb_home() -> String raise MbError {
  let explicit = env_or("MB_HOME", "")
  if explicit != "" {
    return explicit
  }
  let xdg = env_or("XDG_DATA_HOME", "")
  if xdg != "" {
    return path_join(xdg, "mb")
  }
  path_join(path_join(home_dir(), ".local/share"), "mb")
}

///|
/// Directory that receives executables. Defaults to `~/.local/bin`, matching
/// the requirement that every install lands there.
pub fn bin_dir() -> String raise MbError {
  let explicit = env_or("MB_BIN_DIR", "")
  if explicit != "" {
    explicit
  } else {
    path_join(home_dir(), ".local/bin")
  }
}

///|
pub fn dir_exists(path : String) -> Bool {
  @fs.is_dir(path) catch {
    _ => false
  }
}

///|
pub fn file_exists(path : String) -> Bool {
  @fs.is_file(path) catch {
    _ => false
  }
}

///|
pub fn path_exists(path : String) -> Bool {
  @fs.path_exists(path)
}

///|
/// `mkdir -p` for a single path.
pub fn mkdir_p(path : String) -> Unit raise MbError {
  if path == "" || path == "/" {
    return
  }
  if dir_exists(path) {
    return
  }
  let mut cur = if path.has_prefix("/") { "/" } else { "" }
  for part in path.split("/") {
    let seg = part.to_owned()
    if seg == "" {
      continue
    }
    if cur == "" {
      cur = seg
    } else if cur == "/" {
      cur = "/" + seg
    } else {
      cur = cur + "/" + seg
    }
    if !path_exists(cur) {
      @fs.create_dir(cur) catch {
        _ => raise MbError("failed to create directory: " + cur)
      }
    }
  }
}

///|
/// `rm -rf`. Delegates to the system tool so symlinks, read-only entries and
/// large trees are all handled correctly.
pub fn rm_rf(path : String) -> Unit raise MbError {
  if path == "" || !path_exists(path) {
    return
  }
  if path == "/" {
    raise MbError("refusing to remove the filesystem root")
  }
  if !run_ok("rm -rf -- " + shell_quote(path)) {
    raise MbError("failed to remove: " + path)
  }
}

///|
/// Names (without the directory prefix) of entries in `path`. Returns an empty
/// array when the directory cannot be read.
pub fn list_dir_unsafe(path : String) -> Array[String] {
  let entries = @fs.read_dir(path) catch { _ => return [] }
  let out : Array[String] = []
  for e in entries {
    out.push(e)
  }
  out
}

///|
/// Like `list_dir_unsafe` but reports failures.
pub fn list_dir(path : String) -> Array[String] raise MbError {
  let entries = @fs.read_dir(path) catch {
    _ => raise MbError("failed to read directory: " + path)
  }
  let out : Array[String] = []
  for e in entries {
    out.push(e)
  }
  out
}

///|
pub fn read_bytes(path : String) -> Bytes raise MbError {
  @fs.read_file_to_bytes(path) catch {
    _ => raise MbError("failed to read file: " + path)
  }
}

///|
pub fn read_text(path : String) -> String raise MbError {
  @fs.read_file_to_string(path) catch {
    _ => raise MbError("failed to read file: " + path)
  }
}

///|
pub fn write_bytes(path : String, data : Bytes) -> Unit raise MbError {
  let parent = parent_dir(path)
  if parent != "" {
    mkdir_p(parent)
  }
  @fs.write_bytes_to_file(path, data) catch {
    _ => raise MbError("failed to write file: " + path)
  }
}

///|
pub fn write_text(path : String, text : String) -> Unit raise MbError {
  let parent = parent_dir(path)
  if parent != "" {
    mkdir_p(parent)
  }
  @fs.write_string_to_file(path, text) catch {
    _ => raise MbError("failed to write file: " + path)
  }
}

///|
pub fn parent_dir(path : String) -> String {
  match path.rev_find("/") {
    Some(i) if i == 0 => "/"
    Some(i) => path[:i].to_owned()
    None => ""
  }
}

///|
pub fn base_name(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path[i + 1:].to_owned()
    None => path
  }
}

///|
/// Recursively collect regular files below `dir` (absolute or relative to
/// `dir`), returned with `dir`-relative prefixes.
pub fn walk_files(dir : String) -> Array[String] raise MbError {
  let out : Array[String] = []
  walk_into(dir, "", out)
  out
}

///|
fn walk_into(
  root : String,
  rel : String,
  out : Array[String],
) -> Unit raise MbError {
  let here = if rel == "" { root } else { path_join(root, rel) }
  for name in list_dir(here) {
    let child_rel = if rel == "" { name } else { rel + "/" + name }
    let child_abs = path_join(root, child_rel)
    if dir_exists(child_abs) {
      walk_into(root, child_rel, out)
    } else if file_exists(child_abs) {
      out.push(child_rel)
    }
  }
}

///|
/// Copy a regular file, creating parent directories as needed.
pub fn copy_file(src : String, dst : String) -> Unit raise MbError {
  write_bytes(dst, read_bytes(src))
  chmod_exec_if(dst, is_executable_file(src))
}

///|
fn chmod_exec_if(path : String, yes : Bool) -> Unit {
  if yes {
    chmod_exec(path)
  }
}

///|
pub fn chmod_exec(path : String) -> Unit {
  ignore(mb_chmod_exec(cstring(path)))
}

///|
/// True when the file is a native *executable* (ELF or Mach-O), as opposed
/// to a relocatable object file which shares the same leading magic.
pub fn is_executable_file(path : String) -> Bool {
  let data = read_bytes(path) catch { _ => return false }
  if data.length() < 20 {
    return false
  }
  let b0 = data[0].to_int() & 0xff
  let b1 = data[1].to_int() & 0xff
  let b2 = data[2].to_int() & 0xff
  let b3 = data[3].to_int() & 0xff
  // ELF: 0x7f 'E' 'L' 'F'; e_type at offset 16 (2: ET_EXEC, 3: ET_DYN).
  if b0 == 0x7f && b1 == 0x45 && b2 == 0x4c && b3 == 0x46 {
    let little = (data[5].to_int() & 0xff) == 1
    let e_type = if little {
      (data[16].to_int() & 0xff) | ((data[17].to_int() & 0xff) << 8)
    } else {
      ((data[16].to_int() & 0xff) << 8) | (data[17].to_int() & 0xff)
    }
    return e_type == 2 || e_type == 3
  }
  // Mach-O: filetype (MH_EXECUTE = 2) is a u32 at offset 12.
  let ft_le = (data[12].to_int() & 0xff) |
    ((data[13].to_int() & 0xff) << 8) |
    ((data[14].to_int() & 0xff) << 16) |
    ((data[15].to_int() & 0xff) << 24)
  let ft_be = ((data[12].to_int() & 0xff) << 24) |
    ((data[13].to_int() & 0xff) << 16) |
    ((data[14].to_int() & 0xff) << 8) |
    (data[15].to_int() & 0xff)
  let mach_o_le_32 = b0 == 0xce && b1 == 0xfa && b2 == 0xed && b3 == 0xfe
  let mach_o_le_64 = b0 == 0xcf && b1 == 0xfa && b2 == 0xed && b3 == 0xfe
  let mach_o_be_32 = b0 == 0xfe && b1 == 0xed && b2 == 0xfa && b3 == 0xce
  let mach_o_be_64 = b0 == 0xfe && b1 == 0xed && b2 == 0xfa && b3 == 0xcf
  if mach_o_le_32 || mach_o_le_64 {
    return ft_le == 2
  }
  if mach_o_be_32 || mach_o_be_64 {
    return ft_be == 2
  }
  // Universal (fat) binaries are also acceptable.
  b0 == 0xca && b1 == 0xfe && b2 == 0xba && b3 == 0xbe
}

///|
/// NUL-terminated byte view for C entry points.
pub fn cstring(s : String) -> Bytes {
  @utf8.encode(s) + Bytes::make(1, (0).to_byte())
}

///|
/// Run a shell command, inheriting stdio. Returns the exit code.
pub fn run_status(cmd : String) -> Int32 {
  mb_system(cstring(cmd))
}

///|
/// Run a shell command and capture its combined output.
pub fn run_capture(cmd : String) -> String {
  @utf8.decode_lossy(mb_popen(cstring(cmd)))
}

///|
/// Run a shell command, raising when it exits non-zero.
pub fn run_checked(cmd : String) -> Unit raise MbError {
  let code = run_status(cmd)
  if code != 0 {
    raise MbError("command failed (exit \{code}): " + cmd)
  }
}

///|
/// Run a shell command, returning whether it succeeded.
pub fn run_ok(cmd : String) -> Bool {
  run_status(cmd) == 0
}

///|
/// Single-quote a string for safe interpolation into a `/bin/sh` command.
pub fn shell_quote(s : String) -> String {
  "'" + s.replace(old="'", new="'\\''") + "'"
}

///|
/// SHA-256 of `data` as a lowercase hex string.
pub fn sha256_hex(data : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(data))
}

///|
/// The platform triple used to select MoonBit toolchain archives.
pub fn platform() -> String raise MbError {
  let p = @utf8.decode_lossy(mb_platform())
  if p == "" {
    raise MbError("unsupported platform: mb only supports Linux and macOS")
  } else {
    p
  }
}

///|
pub fn is_tty() -> Bool {
  mb_isatty_stdout() != 0
}
