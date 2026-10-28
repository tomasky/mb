///|
/// Prebuilt release artifacts.
///
/// `mb tool install` prefers a binary published on the module's GitHub release
/// over compiling from source. This module locates the repository behind a
/// mooncakes module, queries the GitHub releases API, picks an asset that
/// matches the host platform and installs it, unpacking archives when needed.
/// When nothing suitable is found the caller falls back to building from
/// source.

///|
/// Extract the `owner/repo` slug from a GitHub repository URL. Returns `None`
/// for empty values and for hosts other than github.com.
fn parse_github_repo(url : String) -> String? {
  let mut s = url.trim()
  if s == "" {
    return None
  }
  while s.has_suffix("/") {
    s = s[:s.length() - 1].to_owned()
  }
  if s.has_suffix(".git") {
    s = s[:s.length() - 4].to_owned()
  }
  let prefixes = [
    "https://github.com/", "http://github.com/", "git://github.com/", "ssh://git@github.com/",
    "git@github.com:",
  ]
  let mut rest = ""
  let mut found = false
  for p in prefixes {
    if s.has_prefix(p) {
      rest = s[p.length():].to_owned()
      found = true
      break
    }
  }
  if !found {
    // Also accept a bare `owner/repo` slug, which is how a package that is
    // not on mooncakes.io is named on the command line. Reject anything that
    // looks like a URL for another host.
    if s.contains("://") || s.contains(":") {
      return None
    }
    rest = s.to_owned()
  }
  let parts = rest.split("/").to_array()
  if parts.length() < 2 {
    return None
  }
  let owner = parts[0].to_owned()
  let repo = parts[1].to_owned()
  if owner == "" || repo == "" || (!found && owner.contains(".")) {
    None
  } else {
    Some(owner + "/" + repo)
  }
}

///|
/// Split a `owner/repo@version` spec (or URL) into its repository part and the
/// optional version. A `@` that belongs to a `git@github.com:` remote is left
/// alone.
fn split_github_version(spec : String) -> (String, String?) {
  let s = spec.trim()
  match s.rev_find("@") {
    Some(i) => {
      let after = s[i + 1:].to_owned()
      if after.contains("/") {
        (s.to_owned(), None)
      } else {
        (s[:i].to_owned(), Some(after))
      }
    }
    None => (s.to_owned(), None)
  }
}

///|
/// Parse a command-line package spec as a GitHub repository, returning
/// `(owner/repo, version?)`. Accepts `owner/repo`, `owner/repo@v`, full URLs
/// and `git@github.com:` remotes.
fn parse_github_spec(spec : String) -> (String, String?)? {
  let (base, version) = split_github_version(spec)
  match parse_github_repo(base) {
    Some(repo) => Some((repo, version))
    None => None
  }
}

///|
/// CPU-architecture aliases that identify the host `plat` triple.
fn arch_aliases(plat : String) -> Array[String] {
  if plat.contains("x86_64") {
    ["x86_64", "amd64", "x64", "x86-64"]
  } else if plat.contains("aarch64") || plat.contains("arm64") {
    ["aarch64", "arm64"]
  } else {
    []
  }
}

///|
/// Operating-system aliases that identify the host `plat` triple.
fn os_aliases(plat : String) -> Array[String] {
  if plat.has_prefix("linux") {
    ["linux"]
  } else if plat.has_prefix("darwin") {
    ["darwin", "macos", "mac", "osx"]
  } else {
    []
  }
}

///|
/// True when an asset name mentions both the host OS and CPU architecture.
///
/// Matching is case-insensitive and accepts common aliases (`amd64`/`x64` for
/// `x86_64`, `arm64` for `aarch64`, `macos` for `darwin`). Requiring both
/// avoids installing a binary built for a different platform.
fn asset_matches_platform(name : String, plat : String) -> Bool {
  let lower = name.to_lower()
  let mut os_ok = false
  for a in os_aliases(plat) {
    if lower.contains(a) {
      os_ok = true
    }
  }
  if !os_ok {
    return false
  }
  let mut arch_ok = false
  for a in arch_aliases(plat) {
    if lower.contains(a) {
      arch_ok = true
    }
  }
  arch_ok
}

///|
/// True for sidecar files that carry a checksum, signature or metadata rather
/// than an installable program.
fn asset_is_checksum(name : String) -> Bool {
  let lower = name.to_lower()
  let suffixes = [
    ".sha256", ".sha256sum", ".sha512", ".sha512sum", ".sha1", ".md5", ".sig", ".asc",
    ".pem", ".crt", ".cert", ".txt", ".json", ".sbom",
  ]
  for s in suffixes {
    if lower.has_suffix(s) {
      return true
    }
  }
  false
}

///|
/// True for assets that can plausibly become an executable on this host: not a
/// checksum, not a native package installer and not a Windows binary.
fn is_installable_asset(name : String) -> Bool {
  if asset_is_checksum(name) {
    return false
  }
  let lower = name.to_lower()
  let excluded = [
    ".deb", ".rpm", ".msi", ".dmg", ".pkg", ".apk", ".exe", ".msix", ".nupkg", ".jar",
  ]
  for s in excluded {
    if lower.has_suffix(s) {
      return false
    }
  }
  true
}

///|
/// True when a name is a platform token rather than part of a tool's name.
fn is_platform_token(token : String) -> Bool {
  match token.to_lower() {
    "linux"
    | "linux64"
    | "darwin"
    | "macos"
    | "macosx"
    | "mac"
    | "osx"
    | "windows"
    | "win"
    | "win32"
    | "win64"
    | "freebsd"
    | "unix"
    | "unknown"
    | "gnu"
    | "musl"
    | "musl64"
    | "msvc"
    | "pc"
    | "apple"
    | "none"
    | "static"
    | "x86"
    | "x86_64"
    | "x86-64"
    | "amd64"
    | "x64"
    | "aarch64"
    | "arm64"
    | "arm"
    | "i386"
    | "i686"
    | "universal"
    | "all"
    | "noarch"
    | "bin"
    | "binary"
    | "release"
    | "dist" => true
    _ => false
  }
}

///|
/// True when a token looks like a version (`1.2.3`, `v1.2.3`).
fn is_version_token(token : String) -> Bool {
  if token == "" {
    return false
  }
  let c0 = token[0]
  if c0 >= '0' && c0 <= '9' {
    return true
  }
  if (c0 == 'v' || c0 == 'V') && token.length() > 1 {
    let c1 = token[1]
    return c1 >= '0' && c1 <= '9'
  }
  false
}

///|
/// The last path segment of a module name (`author/mod` -> `mod`).
fn short_name(name : String) -> String {
  match name.rev_find("/") {
    Some(i) => name[i + 1:].to_owned()
    None => name
  }
}

///|
/// Derive an executable name from a raw (non-archive) asset name by removing
/// archive extensions, version tokens and platform tokens. Returns `""` when
/// nothing meaningful is left, in which case the caller falls back to the
/// module name.
fn binary_name_from_asset(name : String) -> String {
  let mut stem = name
  for i = 0; i < 2; i = i + 1 {
    match strip_archive_ext(stem) {
      Some(s) => stem = s
      None => ()
    }
  }
  let parts = stem
    .replace(old="_", new="-")
    .replace(old=".", new="-")
    .split("-")
    .to_array()
  let kept : Array[String] = []
  for p in parts {
    let tok = p.to_owned()
    if tok == "" || is_platform_token(tok) || is_version_token(tok) {
      continue
    }
    kept.push(tok)
  }
  kept.join("-")
}

///|
/// True for files that are not programs: shared/static libraries, debug
/// symbols and documentation that may live next to an executable.
fn is_library_name(name : String) -> Bool {
  let lower = name.to_lower()
  if lower.contains(".so") {
    return true
  }
  let suffixes = [
    ".dylib", ".dll", ".a", ".o", ".lib", ".rlib", ".pdb", ".dsym", ".h", ".hpp",
    ".txt", ".md", ".json", ".toml", ".html", ".wasm", ".gz", ".zip", ".1", ".pc",
  ]
  for s in suffixes {
    if lower.has_suffix(s) {
      return true
    }
  }
  false
}

///|
/// Request headers for the GitHub API. An authentication token from
/// `GITHUB_TOKEN` or `GH_TOKEN` is included when present, which raises the
/// rate limit from 60 to 5000 requests per hour.
fn github_headers() -> Array[String] {
  let headers = [
    "User-Agent: mb/" + MB_VERSION,
    "Accept: application/vnd.github+json",
    "X-GitHub-Api-Version: 2022-11-28",
  ]
  let token = env_or("GITHUB_TOKEN", env_or("GH_TOKEN", ""))
  if token != "" {
    headers.push("Authorization: Bearer " + token)
  }
  headers
}

///|
/// Fetch a GitHub API document, returning `None` on any error (including a
/// 404 for a missing release) so callers can fall back gracefully.
fn github_json(url : String) -> Json? {
  let text = fetch_text_headers(url, github_headers()) catch { _ => "" }
  if text == "" {
    return None
  }
  let parsed = @json.parse(text) catch { _ => Json::null() }
  match parsed {
    Null => None
    other => Some(other)
  }
}

///|
/// Look up a GitHub release. The pinned version is tried as both `v<version>`
/// and `<version>` tags; when the caller did not pin a version the repository's
/// `latest` release is used as a fallback.
fn fetch_release(repo : String, version : String, allow_latest : Bool) -> Json? {
  let base = "https://api.github.com/repos/" + repo + "/releases/tags/"
  for tag in ["v" + version, version] {
    match github_json(base + tag) {
      Some(j) => return Some(j)
      None => ()
    }
  }
  if allow_latest {
    match
      github_json("https://api.github.com/repos/" + repo + "/releases/latest") {
      Some(j) => return Some(j)
      None => ()
    }
  }
  None
}

///|
fn asset_candidate(asset : Json) -> (String, String, String?)? {
  let name = match json_string(asset, "name") {
    Some(n) => n
    None => return None
  }
  let url = match json_string(asset, "browser_download_url") {
    Some(u) => u
    None => return None
  }
  Some((name, url, json_string(asset, "digest")))
}

///|
/// Choose the asset to install: the first platform-matching archive, else the
/// first platform-matching raw binary. Returns `(name, url, digest?)`.
fn pick_release_asset(
  release : Json,
  plat : String,
) -> (String, String, String?)? {
  let assets = match json_array(release, "assets") {
    Some(a) => a
    None => []
  }
  let mut raw : (String, String, String?)? = None
  for asset in assets {
    match asset_candidate(asset) {
      None => ()
      Some((name, url, digest)) => {
        if !is_installable_asset(name) || !asset_matches_platform(name, plat) {
          continue
        }
        let candidate = (name, url, digest)
        if is_archive_name(name) {
          return Some(candidate)
        } else if raw is None {
          raw = Some(candidate)
        }
      }
    }
  }
  raw
}

///|
/// Normalise a GitHub asset digest (`sha256:<hex>`) to its hex part.
fn sha256_of_digest(digest : String) -> String? {
  let lower = digest.to_lower()
  if lower.has_prefix("sha256:") {
    Some(lower[7:].to_owned())
  } else {
    None
  }
}

///|
/// Executables found inside an unpacked archive, as `(name, path)` pairs. Names
/// are deduplicated so a file that appears twice is installed once.
fn collect_executables(dir : String) -> Array[(String, String)] raise MbError {
  let out : Array[(String, String)] = []
  for rel in walk_files(dir) {
    let abs = path_join(dir, rel)
    if !is_executable_file(abs) {
      continue
    }
    let raw = base_name(rel)
    if is_library_name(raw) {
      continue
    }
    let name = if raw.has_suffix(".exe") {
      raw[:raw.length() - 4].to_owned()
    } else {
      raw
    }
    let mut dup = false
    for existing in out {
      if existing.0 == name {
        dup = true
      }
    }
    if !dup {
      out.push((name, abs))
    }
  }
  out
}

///|
/// Try to install `name` `version` from a prebuilt GitHub release asset.
///
/// Returns the installed executable names on success, or `None` when the
/// module has no usable release for this platform, in which case the caller
/// should build from source. `requested` is the version the user pinned, if
/// any; it gates the `/releases/latest` fallback.
fn try_install_release(
  name : String,
  version : String,
  repository : String,
  requested : String?,
  bin : String,
  dir : String,
  force : Bool,
  interactive : Bool,
) -> Array[String]? raise MbError {
  let repo = match parse_github_repo(repository) {
    Some(r) => r
    None => return None
  }
  let plat = platform()
  let release = match fetch_release(repo, version, requested is None) {
    Some(r) => r
    None => return None
  }
  let (asset_name, url, digest) = match pick_release_asset(release, plat) {
    Some(p) => p
    None => return None
  }
  println("Found release asset " + asset_name + " for " + plat)
  Some(
    download_and_install_asset(
      asset_name,
      url,
      digest,
      short_name(name),
      bin,
      dir,
      force,
      interactive,
    ),
  )
}

///|
/// Download one release asset and install its executable(s) into `bin`.
///
/// Archives are unpacked and every executable inside is installed; a plain file
/// is installed under a name derived from the asset, falling back to
/// `fallback_name` when the asset name carries no usable name.
fn download_and_install_asset(
  asset_name : String,
  url : String,
  digest : String?,
  fallback_name : String,
  bin : String,
  dir : String,
  force : Bool,
  interactive : Bool,
) -> Array[String] raise MbError {
  println("Downloading " + url + " ...")
  let tmp = temp_path()
  download(url, tmp, true)
  match digest {
    Some(d) =>
      match sha256_of_digest(d) {
        Some(expected) => {
          let actual = sha256_hex(read_bytes(tmp))
          if actual != expected {
            rm_rf(tmp) catch {
              _ => ()
            }
            raise MbError("checksum mismatch for " + asset_name)
          }
        }
        None => ()
      }
    None => ()
  }
  let installed : Array[String] = []
  if is_archive_name(asset_name) {
    let unpack = temp_path() + ".d"
    extract_archive(tmp, asset_name, unpack)
    let found = collect_executables(unpack)
    let all_names : Array[String] = []
    for (n, _) in found {
      all_names.push(n)
    }
    let names = choose_names(all_names, interactive)
    ensure_bin_free(bin, names, dir, force)
    for entry in found {
      let (bin_name, path) = entry
      if in_array(names, bin_name) {
        stage_binary(dir, bin_name, path)
        installed.push(bin_name)
      }
    }
    rm_rf(unpack) catch {
      _ => ()
    }
  } else {
    let derived = binary_name_from_asset(asset_name)
    let bin_name = if derived == "" { fallback_name } else { derived }
    ensure_bin_free(bin, [bin_name], dir, force)
    stage_binary(dir, bin_name, tmp)
    installed.push(bin_name)
  }
  rm_rf(tmp) catch {
    _ => ()
  }
  if installed.is_empty() {
    raise MbError("no executable found in release asset " + asset_name)
  }
  link_binaries(bin, dir, installed)
  report_installed(bin, installed)
  installed
}

///|
/// Latest release tag of a GitHub repository, or `None` when there is none or
/// the API could not be reached.
fn latest_github_tag(repo : String) -> String? {
  match
    github_json("https://api.github.com/repos/" + repo + "/releases/latest") {
    Some(j) => json_string(j, "tag_name")
    None => None
  }
}

///|
/// Install a tool that is not on mooncakes.io straight from a GitHub release.
///
/// `spec` is `owner/repo`, `owner/repo@version` or a GitHub URL. The recorded
/// tool name is the repository slug and the version is the release tag.
fn install_github_tool(
  spec : String,
  bin : String,
  force : Bool,
  interactive : Bool,
) -> Unit raise MbError {
  let (repo, requested) = match parse_github_spec(spec) {
    Some(p) => p
    None =>
      raise MbError(
        "'" +
        spec +
        "' is neither a mooncakes.io module nor a GitHub repository",
      )
  }
  let version = match requested {
    Some(v) => v
    None => ""
  }
  println("Trying GitHub releases for " + repo + " ...")
  let release = match fetch_release(repo, version, requested is None) {
    Some(r) => r
    None => raise MbError("no GitHub release found for " + repo)
  }
  let tag = match json_string(release, "tag_name") {
    Some(t) => t
    None => if version == "" { "latest" } else { version }
  }
  let dir = tool_dir(repo, tag)
  if file_exists(path_join(dir, "tool.json")) && !force {
    println(
      repo + " " + tag + " is already installed; use --force to reinstall",
    )
    return
  }
  let plat = platform()
  let (asset_name, url, digest) = match pick_release_asset(release, plat) {
    Some(p) => p
    None =>
      raise MbError("no release asset for " + plat + " in " + repo + " " + tag)
  }
  println("Found release asset " + asset_name + " for " + plat)
  let bins = download_and_install_asset(
    asset_name,
    url,
    digest,
    short_name(repo),
    bin,
    dir,
    force,
    interactive,
  )
  let record : ToolMeta = { name: repo, version: tag, bins, bin: Some(bin), }
  write_text(
    path_join(dir, "tool.json"),
    @json.to_json(record).stringify(indent=2),
  )
  println("Installed " + repo + " " + tag + " (prebuilt)")
}
