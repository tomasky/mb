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
/// Fetch `url` and return the response body as bytes.
pub fn fetch_bytes(url : String) -> Bytes raise MbError {
  let tmp = temp_path()
  download(url, tmp, false)
  let data = read_bytes(tmp)
  rm_rf(tmp) catch {
    _ => ()
  }
  data
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
  let cmd = "curl -fL -s" +
    extra +
    " --retry 3 --retry-delay 1 --connect-timeout 30 -o " +
    shell_quote(tmp) +
    " " +
    shell_quote(url)
  let code = run_status(cmd)
  if code != 0 {
    rm_rf(tmp) catch {
      _ => ()
    }
    raise MbError("failed to fetch " + url + " (curl exit \{code})")
  }
  let data = read_bytes(tmp)
  rm_rf(tmp) catch {
    _ => ()
  }
  @utf8.decode_lossy(data)
}

///|
/// Fetch and parse a JSON document.
pub fn fetch_json(url : String) -> Json raise MbError {
  let text = fetch_text(url)
  @json.parse(text) catch {
    _ => raise MbError("invalid JSON returned by " + url)
  }
}
