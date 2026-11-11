///|
/// Network helpers built on the system `curl`.
///
/// `curl` ships with macOS and every mainstream Linux distribution and speaks
/// HTTPS, redirects and retries out of the box. Shelling out to it keeps the
/// tool small while behaving correctly against `cli.moonbitlang.com`,
/// `mooncakes.io` and the CloudFront download endpoints.

///|
/// Create a unique temporary file path and return it.
pub fn temp_path() -> String raise MbError {
  let out = run_capture("mktemp \"${TMPDIR:-/tmp}/mb.XXXXXX\"")
  let path = out.trim().to_owned()
  if path == "" {
    raise MbError("failed to create a temporary file")
  }
  path
}

///|
/// Create a unique temporary directory and return its path.
pub fn temp_dir() -> String raise MbError {
  let out = run_capture("mktemp -d \"${TMPDIR:-/tmp}/mb.XXXXXX\"")
  let path = out.trim().to_owned()
  if path == "" || !dir_exists(path) {
    raise MbError("failed to create a temporary directory")
  }
  path
}

///|
/// Verify the external programs `mb` relies on are present.
pub fn ensure_tools() -> Unit raise MbError {
  let missing = []
  if !run_ok("command -v curl >/dev/null 2>&1") {
    missing.push("curl")
  }
  if !run_ok("command -v tar >/dev/null 2>&1") {
    missing.push("tar")
  }
  if !missing.is_empty() {
    raise MbError(
      "required program(s) not found on PATH: " + missing.join(", "),
    )
  }
}

///|
/// Download `url` to `dest`, following redirects and retrying transient
/// failures. Shows a progress bar for large downloads on a terminal.
pub fn download(
  url : String,
  dest : String,
  progress : Bool,
) -> Unit raise MbError {
  let parent = parent_dir(dest)
  if parent != "" {
    mkdir_p(parent)
  }
  let style = if progress && is_tty() { " --progress-bar" } else { " -s" }
  let cmd = "curl -fL" +
    style +
    " --retry 3 --retry-delay 1 --connect-timeout 30 -o " +
    shell_quote(dest) +
    " " +
    shell_quote(url)
  let code = run_status(cmd)
  if code != 0 {
    rm_rf(dest) catch {
      _ => ()
    }
    raise MbError("failed to download " + url + " (curl exit \{code})")
  }
}

///|
/// Read a temporary download and always remove it afterwards, so a failure
/// while reading does not leak the file.
fn take_temp(tmp : String) -> Bytes raise MbError {
  let data = read_bytes(tmp) catch {
    MbError(m) => {
      try_remove(tmp)
      raise MbError(m)
    }
    Coded(m, c) => {
      try_remove(tmp)
      raise Coded(m, c)
    }
  }
  try_remove(tmp)
  data
}

///|
/// Fetch `url` and return the response body as bytes.
pub fn fetch_bytes(url : String) -> Bytes raise MbError {
  let tmp = temp_path()
  fetch_to_temp(url, tmp, "")
  take_temp(tmp)
}

///|
/// Download `url` to `dest` with quiet curl options, cleaning up on failure.
fn fetch_to_temp(
  url : String,
  dest : String,
  extra : String,
) -> Unit raise MbError {
  let cmd = "curl -fL -s" +
    extra +
    " --retry 3 --retry-delay 1 --connect-timeout 30 -o " +
    shell_quote(dest) +
    " " +
    shell_quote(url)
  let code = run_status(cmd)
  if code != 0 {
    try_remove(dest)
    raise MbError("failed to fetch " + url + " (curl exit \{code})")
  }
}

///|
/// Fetch `url` and return the response body as text.
pub fn fetch_text(url : String) -> String raise MbError {
  @utf8.decode_lossy(fetch_bytes(url))
}

///|
/// Fetch `url` with extra request headers and return the body as text. Used
/// for the GitHub API, which asks callers to identify themselves.
fn fetch_text_headers(
  url : String,
  headers : Array[String],
) -> String raise MbError {
  let tmp = temp_path()
  let mut extra = ""
  for h in headers {
    extra = extra + " -H " + shell_quote(h)
  }
  fetch_to_temp(url, tmp, extra)
  @utf8.decode_lossy(take_temp(tmp))
}

///|
/// Parse the status code printed by `curl -w '%{http_code}'`.
fn parse_http_code(raw : String) -> Int32 {
  let mut n = 0
  let mut any = false
  for c in raw.trim().to_owned().to_array() {
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
      any = true
    } else if any {
      break
    }
  }
  if any {
    n
  } else {
    0
  }
}

///|
/// GET `url` and return `(status_code, body)`. A status of `0` means the
/// request could not be made at all (DNS, TLS, timeout, ...).
fn http_get_status(url : String) -> (Int32, String) raise MbError {
  let tmp = temp_path()
  let cmd = "curl -sL --retry 3 --retry-delay 1 --connect-timeout 30 -o " +
    shell_quote(tmp) +
    " -w '%{http_code}' " +
    shell_quote(url)
  let code = parse_http_code(run_capture(cmd))
  let body = read_text(tmp) catch { MbError(_) | Coded(_, _) => "" }
  try_remove(tmp)
  (code, body)
}

///|
/// Fetch and parse a JSON document.
pub fn fetch_json(url : String) -> Json raise MbError {
  let text = fetch_text(url)
  @json.parse(text) catch {
    _ => raise MbError("invalid JSON returned by " + url)
  }
}
