///|
/// dotenv parsing, env file layout and key management.
///
/// Scope layout:
///
/// - project (default): `./.env`, with `./.mbenv` also loaded when present;
/// - global (`--global`): `$HOME/.mbenv`, which additionally stores the
///   encryption key on a `# mb-env-key:` directive line.
///
/// Values may be plain (`KEY=value`) or encrypted (`KEY=ENC[...]`), so a file
/// can be listed without the key and a plaintext `.env` keeps working.

///|
/// The directive line that carries the encryption key in `$HOME/.mbenv`.
const ENV_KEY_DIRECTIVE : String = "# mb-env-key:"

///|
/// The global env file: `$HOME/.mbenv`.
pub fn global_env_file() -> String raise MbError {
  path_join(home_dir(), ".mbenv")
}

///|
/// Parse a single dotenv line into a key/value pair. Blank lines, comments and
/// lines without `=` are skipped. Returns the raw value (still `ENC[...]` when
/// encrypted).
pub fn parse_dotenv_line(line : String) -> (String, String)? {
  let s = line.trim()
  if s == "" || s.has_prefix("#") {
    return None
  }
  let body = if s.has_prefix("export ") {
    s[7:].trim().to_owned()
  } else {
    s.to_owned()
  }
  match body.find("=") {
    None => None
    Some(i) => {
      let key = body[:i].trim().to_owned()
      if key == "" {
        return None
      }
      Some((key, parse_dotenv_value(body[i + 1:].trim().to_owned())))
    }
  }
}

///|
/// Unquote and unescape a raw dotenv value.
fn parse_dotenv_value(raw : String) -> String {
  let chars = raw.to_array()
  if chars.length() >= 2 {
    let first = chars[0]
    let last = chars[chars.length() - 1]
    if first == '"' && last == '"' {
      return unescape_double(raw[1:raw.length() - 1].to_owned())
    }
    if first == '\'' && last == '\'' {
      return raw[1:raw.length() - 1].to_owned()
    }
  }
  // An unquoted `#` starts a trailing comment.
  match raw.find(" #") {
    Some(i) => raw[:i].trim().to_owned()
    None => raw
  }
}

///|
fn unescape_double(s : String) -> String {
  let chars = s.to_array()
  let out : Array[String] = []
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '\\' && i + 1 < chars.length() {
      let c = chars[i + 1]
      if c == 'n' {
        out.push("\n")
      } else if c == 't' {
        out.push("\t")
      } else {
        out.push(c.to_string())
      }
      i = i + 2
    } else {
      out.push(chars[i].to_string())
      i = i + 1
    }
  }
  out.join("")
}

///|
/// Quote a plain value so it round-trips through the parser.
pub fn format_dotenv_value(value : String) -> String {
  if value == "" {
    return "\"\""
  }
  let needs_quotes = value.contains_char(' ') ||
    value.contains_char('\t') ||
    value.contains_char('#') ||
    value.contains_char('"') ||
    value.contains_char('\'') ||
    value.contains_char('\n') ||
    value.contains_char('\\')
  if !needs_quotes {
    return value
  }
  let escaped = value
    .replace(old="\\", new="\\\\")
    .replace(old="\"", new="\\\"")
    .replace(old="\n", new="\\n")
    .replace(old="\t", new="\\t")
  "\"" + escaped + "\""
}

///|
/// Render one entry as a dotenv line. Encrypted values are written verbatim.
pub fn format_dotenv_line(key : String, value : String) -> String {
  if is_encrypted_value(value) {
    key + "=" + value
  } else {
    key + "=" + format_dotenv_value(value)
  }
}

///|
/// Parse the text of a dotenv file.
pub fn parse_dotenv(text : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for line in text.split("\n") {
    match parse_dotenv_line(line.to_owned()) {
      Some(pair) => out.push(pair)
      None => ()
    }
  }
  out
}

///|
/// Read and parse a dotenv file, returning an empty list when it is absent.
pub fn read_env_file(path : String) -> Array[(String, String)] {
  if !file_exists(path) {
    return []
  }
  let text = read_text(path) catch { _ => return [] }
  parse_dotenv(text)
}

///|
/// Write entries to a dotenv file, replacing its contents.
pub fn write_env_file(
  path : String,
  entries : Array[(String, String)],
) -> Unit raise MbError {
  let lines : Array[String] = []
  for entry in entries {
    let (key, value) = entry
    lines.push(format_dotenv_line(key, value))
  }
  let body = if lines.is_empty() { "" } else { lines.join("\n") + "\n" }
  write_text(path, body)
}

///|
/// Read `$HOME/.mbenv`, splitting out the key directive from the entries.
pub fn read_global_env() -> (String?, Array[(String, String)]) raise MbError {
  let path = global_env_file()
  if !file_exists(path) {
    return (None, [])
  }
  let text = read_text(path) catch { _ => return (None, []) }
  let mut key : String? = None
  let entries : Array[(String, String)] = []
  for line in text.split("\n") {
    let l = line.trim()
    if l.has_prefix(ENV_KEY_DIRECTIVE) {
      let k = l[ENV_KEY_DIRECTIVE.length():].trim().to_owned()
      if k != "" {
        key = Some(k)
      }
    } else {
      match parse_dotenv_line(line.to_owned()) {
        Some(pair) => entries.push(pair)
        None => ()
      }
    }
  }
  (key, entries)
}

///|
/// Write `$HOME/.mbenv`, preserving the key directive.
pub fn write_global_env(
  key : String?,
  entries : Array[(String, String)],
) -> Unit raise MbError {
  let lines : Array[String] = []
  match key {
    Some(k) => lines.push(ENV_KEY_DIRECTIVE + " " + k)
    None => ()
  }
  for entry in entries {
    let (k, v) = entry
    lines.push(format_dotenv_line(k, v))
  }
  let body = if lines.is_empty() { "" } else { lines.join("\n") + "\n" }
  write_text(global_env_file(), body)
}

///|
/// The encryption key: `MB_ENV_KEY` when set, otherwise the directive stored
/// in `$HOME/.mbenv`.
pub fn read_env_key() -> String? raise MbError {
  let from_env = env_or("MB_ENV_KEY", "")
  if from_env != "" {
    return Some(from_env)
  }
  match read_global_env() {
    (Some(k), _) => Some(k)
    (None, _) => None
  }
}

///|
/// Load a dotenv file, decrypting `ENC[...]` values with the available key.
/// Plain values are returned unchanged.
pub fn load_dotenv(path : String) -> Array[(String, String)] raise MbError {
  let entries = read_env_file(path)
  let mut key : String? = None
  let out : Array[(String, String)] = []
  for entry in entries {
    let (k, v) = entry
    if is_encrypted_value(v) {
      let master = match key {
        Some(m) => m
        None => {
          let m = match read_env_key() {
            Some(m) => m
            None =>
              raise MbError(
                "encrypted values in " +
                path +
                " but no key; set MB_ENV_KEY or run `mb env set`",
              )
          }
          key = Some(m)
          m
        }
      }
      out.push((k, decrypt_value(v, master)))
    } else {
      out.push((k, v))
    }
  }
  out
}

///|
/// Load `paths` in order (later files win) and export the values into the
/// current process, so child processes inherit them.
pub fn apply_dotenv(paths : Array[String]) -> Unit raise MbError {
  for path in paths {
    for entry in load_dotenv(path) {
      let (k, v) = entry
      @env.set_env_var(k, v)
    }
  }
}
