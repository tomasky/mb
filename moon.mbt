///|
/// MoonBit toolchain management, the `mb moon` command group.
///
/// This mirrors `uv python`: toolchains are downloaded from
/// `cli.moonbitlang.com`, unpacked into `$MB_HOME/moon/<version>` and can be
/// selected per invocation with `mb run --moon <version>`.

///|
pub const CLI_BASE : String = "https://cli.moonbitlang.com"

///|
/// Root directory holding all installed MoonBit toolchains.
pub fn moon_root() -> String raise MbError {
  path_join(mb_home(), "moon")
}

///|
/// Directory of one installed toolchain.
pub fn toolchain_dir(version : String) -> String raise MbError {
  path_join(moon_root(), version)
}

///|

///|
/// A resolved install request: which URL key to download and what to name the
/// local directory.
pub struct MoonSpec {
  download_key : String
  store_name : String
}

///|
fn urlencode_plus(s : String) -> String {
  s.replace(old="+", new="%2B")
}

///|
/// Parse the `version.json` published at the toolchain root into (name, version)
/// pairs, stripping the descriptive suffix from each version string.
pub fn parse_version_items(j : Json) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  match json_array(j, "items") {
    Some(items) =>
      for item in items {
        match (json_string(item, "name"), json_string(item, "version")) {
          (Some(name), Some(ver)) => out.push((name, first_token(ver)))
          _ => ()
        }
      }
    None => ()
  }
  out
}

///|
fn first_token(s : String) -> String {
  match s.find(" ") {
    Some(i) => s[:i].to_owned()
    None => s
  }
}

///|
/// Latest published `moon` version (e.g. `0.1.20260920`).
pub fn latest_moon_cli_version() -> String? raise MbError {
  let j = fetch_json(CLI_BASE + "/version.json")
  for (name, ver) in parse_version_items(j) {
    if name == "moon" {
      return Some(ver)
    }
  }
  None
}

///|
/// Latest published `moonc` version including its build hash (e.g.
/// `0.10.14+7d59c7ec9`).
pub fn latest_moonc_version() -> String? raise MbError {
  let j = fetch_json(CLI_BASE + "/version.json")
  for (name, ver) in parse_version_items(j) {
    if name == "moonc" {
      let stripped = if ver.has_prefix("v") { ver[1:].to_owned() } else { ver }
      return Some(stripped)
    }
  }
  None
}

///|
/// Turn a user-supplied version into a concrete download key and store name.
///
/// - `latest` / `nightly` map to those aliases; `latest` is stored under the
///   resolved CLI version so repeated installs are idempotent.
/// - A full `moonc` version such as `0.10.14+7d59c7ec9` downloads directly.
/// - A bare compiler version such as `0.10.14` is upgraded to the matching
///   full version when it corresponds to the current release.
pub fn resolve_moon_spec(arg : String) -> MoonSpec raise MbError {
  let a = if arg == "" { "latest" } else { arg }
  if a == "nightly" {
    { download_key: a, store_name: a, }
  } else if a == "latest" {
    let name = match latest_moon_cli_version() {
      Some(v) => v
      None => "latest"
    }
    { download_key: a, store_name: name, }
  } else if a.contains("+") {
    { download_key: a, store_name: a, }
  } else {
    match latest_moonc_version() {
      Some(full) =>
        if full == a || full.has_prefix(a + "+") {
          { download_key: full, store_name: full, }
        } else {
          { download_key: a, store_name: a, }
        }
      None => { download_key: a, store_name: a, }
    }
  }
}

///|
/// Whether a toolchain directory is fully installed (binary plus bundled core).
pub fn toolchain_complete(version : String) -> Bool raise MbError {
  let home = toolchain_dir(version)
  file_exists(path_join(home, "bin/moon")) &&
  dir_exists(path_join(home, "lib/core"))
}

///|
/// Names of installed toolchains.
pub fn installed_toolchains() -> Array[String] raise MbError {
  let root = moon_root()
  if !dir_exists(root) {
    return []
  }
  let out : Array[String] = []
  for name in list_dir(root) {
    if name == "" || name.has_prefix(".") {
      continue
    }
    if dir_exists(path_join(root, name)) {
      out.push(name)
    }
  }
  out
}

///|
/// Path of the file recording the default toolchain version.
fn default_file() -> String raise MbError {
  path_join(moon_root(), ".default")
}

///|
pub fn default_toolchain() -> String? raise MbError {
  let f = default_file()
  if !file_exists(f) {
    return None
  }
  let v = read_text(f).trim().to_owned()
  if v == "" {
    None
  } else {
    Some(v)
  }
}

///|
pub fn set_default_toolchain(version : String) -> Unit raise MbError {
  mkdir_p(moon_root())
  write_text(default_file(), version + "\n")
}

///|
/// Find an installed toolchain matching a user-supplied version. Exact matches
/// win; a bare compiler version also matches its full `+hash` form.
pub fn find_installed_toolchain(version : String) -> String? raise MbError {
  let installed = installed_toolchains()
  for v in installed {
    if v == version {
      return Some(v)
    }
  }
  for v in installed {
    if v.has_prefix(version + "+") {
      return Some(v)
    }
  }
  None
}

///|
/// Pick the toolchain to use when no explicit version is requested.
pub fn effective_toolchain() -> String? raise MbError {
  match default_toolchain() {
    Some(v) => if toolchain_complete(v) { Some(v) } else { None }
    None =>
      match installed_toolchains() {
        [v, ..] => Some(v)
        [] => None
      }
  }
}

///|
/// Download and install a MoonBit toolchain.
pub fn moon_install(arg : String, force : Bool) -> Unit raise MbError {
  ensure_tools()
  let spec = resolve_moon_spec(arg)
  let home = toolchain_dir(spec.store_name)
  if toolchain_complete(spec.store_name) && !force {
    println("MoonBit toolchain \{spec.store_name} is already installed")
    sync_default_shims()
    return
  }
  println("Installing MoonBit toolchain \{spec.store_name} ...")
  rm_rf(home)
  mkdir_p(home)
  let plat = platform()
  let encoded = urlencode_plus(spec.download_key)
  let tar = temp_path()
  download(
    CLI_BASE + "/binaries/" + encoded + "/moonbit-" + plat + ".tar.gz",
    tar,
    true,
  )
  extract_tar_gz(tar, home)
  rm_rf(tar) catch {
    _ => ()
  }
  // Ensure every shipped binary is executable.
  for rel in walk_files(path_join(home, "bin")) {
    chmod_exec(path_join(path_join(home, "bin"), rel))
  }
  // Fetch and bundle the standard library so `moon build` works offline.
  println("Downloading core ...")
  let core_tar = temp_path()
  download(CLI_BASE + "/cores/core-" + encoded + ".tar.gz", core_tar, true)
  extract_tar_gz(core_tar, path_join(home, "lib"))
  rm_rf(core_tar) catch {
    _ => ()
  }
  println("Bundling core ...")
  let moon = path_join(home, "bin/moon")
  let core_dir = path_join(home, "lib/core")
  let prefix = "MOON_HOME=" +
    shell_quote(home) +
    " PATH=" +
    shell_quote(path_join(home, "bin")) +
    ":\"$PATH\" "
  run_checked(
    "cd " +
    shell_quote(core_dir) +
    " && " +
    prefix +
    shell_quote(moon) +
    " bundle --warn-list -a --all",
  )
  run_checked(
    "cd " +
    shell_quote(core_dir) +
    " && " +
    prefix +
    shell_quote(moon) +
    " bundle --warn-list -a --target wasm-gc --quiet",
  )
  // First install becomes the default; otherwise leave the choice alone and
  // just make sure ~/.local/bin reflects whichever version is selected.
  if default_toolchain() is None {
    set_default_toolchain(spec.store_name)
  }
  sync_default_shims()
  println("Installed MoonBit toolchain \{spec.store_name} to " + home)
}

///|
/// Point the `~/.local/bin` symlinks at the currently-selected toolchain.
pub fn sync_default_shims() -> Unit raise MbError {
  match default_toolchain() {
    Some(d) => ensure_shims(d)
    None => ()
  }
}

///|
/// Create or refresh `~/.local/bin` symlinks for the default toolchain's
/// binaries.
pub fn ensure_shims(version : String) -> Unit raise MbError {
  if !toolchain_complete(version) {
    return
  }
  let bin = bin_dir()
  mkdir_p(bin)
  let tbin = path_join(toolchain_dir(version), "bin")
  for name in list_dir_unsafe(tbin) {
    let src = path_join(tbin, name)
    if dir_exists(src) {
      continue
    }
    let link = path_join(bin, name)
    run_ok("ln -sfn " + shell_quote(src) + " " + shell_quote(link)) |> ignore
  }
}

///|
/// The `mb moon list` command.
pub fn moon_list() -> Unit raise MbError {
  let installed = installed_toolchains()
  let default = default_toolchain()
  println("Installed MoonBit toolchains:")
  if installed.is_empty() {
    println("  (none)")
  } else {
    for v in installed {
      let marker = match default {
        Some(d) if d == v => " (default)"
        _ => ""
      }
      println("  " + v + marker)
    }
  }
  let latest = latest_moon_cli_version() catch { _ => None }
  let moonc = latest_moonc_version() catch { _ => None }
  match latest {
    Some(v) => println("\nLatest available: " + v)
    None => ()
  }
  match moonc {
    Some(v) => println("Latest compiler:  " + v)
    None => ()
  }
}

///|
/// The `mb moon uninstall <version>` command.
pub fn moon_uninstall(version : String) -> Unit raise MbError {
  match find_installed_toolchain(version) {
    Some(v) => {
      rm_rf(toolchain_dir(v))
      println("Uninstalled MoonBit toolchain " + v)
      match default_toolchain() {
        Some(d) if d == v => {
          rm_rf(default_file()) catch {
            _ => ()
          }
          // Fall back to another installed toolchain, if any.
          match installed_toolchains() {
            [next, ..] => {
              set_default_toolchain(next)
              ensure_shims(next)
            }
            [] => ()
          }
        }
        _ => ()
      }
    }
    None =>
      raise MbError("no toolchain matching '" + version + "' is installed")
  }
}

///|
/// The `mb moon default <version>` command.
pub fn moon_set_default(version : String) -> Unit raise MbError {
  match find_installed_toolchain(version) {
    Some(v) => {
      set_default_toolchain(v)
      ensure_shims(v)
      println("Default MoonBit toolchain set to " + v)
    }
    None =>
      raise MbError(
        "no toolchain matching '" +
        version +
        "' is installed; run `mb moon install " +
        version +
        "` first",
      )
  }
}

///|
/// The `mb moon which [version]` command.
pub fn moon_which(version : String) -> Unit raise MbError {
  let chosen = if version == "" {
    effective_toolchain()
  } else {
    find_installed_toolchain(version)
  }
  match chosen {
    Some(v) => println(path_join(toolchain_dir(v), "bin/moon"))
    None => raise MbError("no MoonBit toolchain is installed")
  }
}

///|
/// Environment describing how to invoke a MoonBit toolchain.
pub struct ToolchainEnv {
  moon : String
  home : String?
  bin : String?
}

///|
/// A system toolchain discovered on `PATH`.
pub fn system_toolchain() -> ToolchainEnv? {
  let which = run_capture("command -v moon 2>/dev/null").trim().to_owned()
  if which == "" {
    None
  } else {
    Some({ moon: which, home: None, bin: None, })
  }
}

///|
/// Shell prefix that points a command at `tc`'s environment. Empty for the
/// system toolchain.
pub fn env_prefix(tc : ToolchainEnv) -> String {
  match (tc.home, tc.bin) {
    (Some(h), Some(b)) =>
      "MOON_HOME=" + shell_quote(h) + " PATH=" + shell_quote(b) + ":\"$PATH\" "
    _ => ""
  }
}

///|
/// Resolve the toolchain to use for building/installing tools. When `explicit`
/// is empty this prefers the managed default, then a system install, and only
/// then installs the latest release.
pub fn resolve_toolchain(explicit : String) -> ToolchainEnv raise MbError {
  if explicit != "" {
    match find_installed_toolchain(explicit) {
      Some(v) =>
        return {
          moon: path_join(toolchain_dir(v), "bin/moon"),
          home: Some(toolchain_dir(v)),
          bin: Some(path_join(toolchain_dir(v), "bin")),
        }
      None => moon_install(explicit, false)
    }
  }
  match effective_toolchain() {
    Some(v) =>
      {
        moon: path_join(toolchain_dir(v), "bin/moon"),
        home: Some(toolchain_dir(v)),
        bin: Some(path_join(toolchain_dir(v), "bin")),
      }
    None =>
      match system_toolchain() {
        Some(tc) => tc
        None => {
          moon_install("latest", false)
          let v = match effective_toolchain() {
            Some(v) => v
            None => raise MbError("failed to install a MoonBit toolchain")
          }
          {
            moon: path_join(toolchain_dir(v), "bin/moon"),
            home: Some(toolchain_dir(v)),
            bin: Some(path_join(toolchain_dir(v), "bin")),
          }
        }
      }
  }
}
