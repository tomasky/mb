///|
/// Archive extraction helpers.
///
/// `.zip` archives (mooncakes.io package sources) are decoded in-process with
/// `bobzhang/zip`, which keeps the tool portable to any Linux/macOS host
/// without requiring `unzip`. `.tar.gz` archives (MoonBit toolchain builds)
/// are handled by the system `tar`, which is present on every supported host.

///|
/// Extract a zip archive from memory into `dest`.
///
/// Entry paths are sanitised to prevent `..` escapes from writing outside
/// `dest`. Symlink entries are ignored: only regular files and directories are
/// materialised.
pub fn extract_zip(zip_bytes : Bytes, dest : String) -> Unit raise MbError {
  let archive = @zip.Archive::of_bytes(zip_bytes) catch {
    _ => raise MbError("failed to parse zip archive")
  }
  mkdir_p(dest)
  for entry in archive.to_array() {
    let raw = @fpath.sanitize(entry.path()).to_string()
    if raw == "" ||
      raw.has_prefix("/") ||
      raw == ".." ||
      raw.has_prefix("../") ||
      raw.contains("/../") {
      continue
    }
    let out = path_join(dest, raw)
    if entry.is_dir() {
      mkdir_p(out)
    } else if entry.is_file() {
      let content = match entry.kind() {
        File(f) =>
          f.to_bytes() catch {
            _ => raise MbError("failed to decompress zip member: " + raw)
          }
        Dir => continue
      }
      write_bytes(out, content)
    }
  }
}

///|
/// Extract a `.tar.gz` archive on disk into `dest` using the system `tar`.
pub fn extract_tar_gz(archive : String, dest : String) -> Unit raise MbError {
  mkdir_p(dest)
  let cmd = "tar -xzf " + shell_quote(archive) + " -C " + shell_quote(dest)
  run_checked(cmd) catch {
    _ => raise MbError("failed to extract tar archive: " + archive)
  }
}
