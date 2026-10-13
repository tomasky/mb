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

///|
/// Archive suffixes `mb` knows how to unpack, longest first so that
/// `.tar.gz` is recognised before the bare `.gz`.
fn archive_suffixes() -> Array[String] {
  [
    ".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".tgz", ".txz", ".tbz2", ".zip",
    ".tar", ".gz", ".xz", ".bz2", ".zst",
  ]
}

///|
/// True when `name` ends in a suffix `mb` can unpack (`zip`, `tar`, `gz`,
/// `xz`, `bz2`, `zst`, ...). A name without such a suffix is treated as an
/// uncompressed file.
fn is_archive_name(name : String) -> Bool {
  let lower = name.to_lower()
  for suffix in archive_suffixes() {
    if lower.has_suffix(suffix) {
      return true
    }
  }
  false
}

///|
/// Remove one archive suffix from `s`, if present.
fn strip_archive_ext(s : String) -> String? {
  let lower = s.to_lower()
  for suffix in archive_suffixes() {
    if lower.has_suffix(suffix) {
      return Some(s[:s.length() - suffix.length()].to_owned())
    }
  }
  None
}

///|
/// True when `name` names a tar container, optionally compressed (`.tar`,
/// `.tar.gz`, `.tgz`, `.tar.xz`, `.txz`, `.tar.bz2`, `.tar.zst`).
fn is_tar_archive(name : String) -> Bool {
  let lower = name.to_lower()
  let suffixes = [
    ".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".tgz", ".txz", ".tbz2", ".tar",
  ]
  for s in suffixes {
    if lower.has_suffix(s) {
      return true
    }
  }
  false
}

///|
/// Command that writes a single compressed file to stdout, for the formats
/// that are not (necessarily) tar containers.
fn decompress_command(name : String) -> String? {
  let lower = name.to_lower()
  if lower.has_suffix(".gz") {
    Some("gzip -dc")
  } else if lower.has_suffix(".xz") {
    Some("xz -dc")
  } else if lower.has_suffix(".bz2") {
    Some("bzip2 -dc")
  } else if lower.has_suffix(".zst") {
    Some("zstd -dc")
  } else {
    None
  }
}

///|
/// Unpack a downloaded archive into `dest`, regardless of whether it is a
/// `zip`, a `tar` container (optionally compressed) or a bare compressed file.
///
/// `name` is the original asset name; its suffix decides how to unpack, which
/// keeps the behaviour independent of the temporary file's own name.
fn extract_archive(
  path : String,
  name : String,
  dest : String,
) -> Unit raise MbError {
  mkdir_p(dest)
  let lower = name.to_lower()
  if lower.has_suffix(".zip") {
    extract_zip(read_bytes(path), dest)
    return
  }
  if is_tar_archive(name) {
    // `tar -xf` auto-detects the compression of `.tar`, `.tar.gz`, `.tgz`,
    // `.tar.xz`, `.txz`, `.tar.bz2` and `.tar.zst` on GNU tar and bsdtar.
    run_checked("tar -xf " + shell_quote(path) + " -C " + shell_quote(dest)) catch {
      _ => raise MbError("failed to extract archive: " + name)
    }
    return
  }
  // A bare compressed file: decompress it into `dest`.
  match decompress_command(name) {
    Some(cmd) => {
      let stem = match strip_archive_ext(name) {
        Some(s) => s
        None => name
      }
      let out = path_join(dest, base_name(stem))
      run_checked(cmd + " " + shell_quote(path) + " > " + shell_quote(out)) catch {
        _ => raise MbError("failed to extract archive: " + name)
      }
    }
    None => raise MbError("failed to extract archive: " + name)
  }
}
