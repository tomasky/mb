///|
/// Tool management, the `mb tool` command group.
///
/// A "tool" is a mooncakes.io module that publishes at least one executable
/// package. `mb tool install` downloads the module source, compiles it with a
/// managed (or system) MoonBit toolchain and copies the resulting native
/// binaries into `~/.local/bin`.

///|
pub const MOONCAKES_API : String = "https://mooncakes.io"

///|
pub const MOONCAKES_DOWNLOAD : String = "https://download.mooncakes.io"

///|
/// Persisted metadata for one installed tool version. `bin` records where the
/// executables were copied; it is optional because records written before it
/// existed only have `bins`.
pub struct ToolMeta {
  name : String
  version : String
  bins : Array[String]
  bin : String?
} derive(ToJson, FromJson)

///|
pub extend ToolMeta with ToJson::{to_json}

///|
pub extend ToolMeta with @json.FromJson::{from_json}

///|
/// Root directory holding all installed tools.
pub fn tool_root() -> String raise MbError {
  path_join(mb_home(), "tool")
}

///|
fn tool_key(name : String) -> String {
  name.replace(old="/", new="-")
}

///|
/// Directory for one tool version.
pub fn tool_dir(name : String, version : String) -> String raise MbError {
  path_join(path_join(tool_root(), tool_key(name)), version)
}

///|
fn split_spec(spec : String) -> (String, String?) raise MbError {
  match spec.split_once("@") {
    Some((m, v)) => (m.to_owned(), Some(v.to_owned()))
    None =>
      if spec == "" {
        raise MbError(
          "expected a package name in the form <author>/<module>[@<version>]",
        )
      } else {
        (spec, None)
      }
  }
}

///|
/// Fetch the registry manifest for a module, optionally pinned to a version.
pub fn fetch_manifest(name : String, version : String?) -> Json raise MbError {
  let url = match version {
    Some(v) => MOONCAKES_API + "/api/v0/manifest/" + name + "@" + v
    None => MOONCAKES_API + "/api/v0/manifest/" + name
  }
  let j = fetch_json(url) catch {
    _ => raise MbError("module '" + name + "' was not found on mooncakes.io")
  }
  match json_object(j, "metadata") {
    Some(_) => j
    None =>
      raise MbError("mooncakes.io returned no metadata for '" + name + "'")
  }
}

///|
/// Discover native executables produced by `moon build` under `src`.
///
/// MoonBit writes native binaries as `<name>.exe`; we additionally verify the
/// file magic so non-executable artefacts are ignored.
pub fn discover_binaries(src : String) -> Array[(String, String)] raise MbError {
  let out : Array[(String, String)] = []
  let build = path_join(src, "_build/native/release/build")
  if !dir_exists(build) {
    return out
  }
  for rel in walk_files(build) {
    let abs = path_join(build, rel)
    if !is_executable_file(abs) {
      continue
    }
    let raw = base_name(rel)
    let tool_name = if raw.has_suffix(".exe") {
      raw[:raw.length() - 4].to_owned()
    } else {
      raw
    }
    out.push((tool_name, abs))
  }
  out
}

///|
/// Compile the extracted source at `src` with `tc` and return the discovered
/// binaries.
pub fn build_tool(
  src : String,
  tc : ToolchainEnv,
) -> Array[(String, String)] raise MbError {
  let prefix = env_prefix(tc)
  let cmd = "cd " +
    shell_quote(src) +
    " && " +
    prefix +
    shell_quote(tc.moon) +
    " build --target native --release"
  run_checked(cmd) catch {
    _ => raise MbError("failed to build the tool in " + src)
  }
  let bins = discover_binaries(src)
  if bins.is_empty() {
    raise MbError(
      "no native executable was produced; this module does not publish a runnable package",
    )
  }
  bins
}

///|
/// Install one tool from a `<author>/<module>[@<version>]` spec.
pub fn tool_install(
  spec : String,
  toolchain_override : String,
  bin_override : String,
  force : Bool,
) -> Unit raise MbError {
  ensure_tools()
  let bin_dir = if bin_override != "" { bin_override } else { bin_dir() }
  let (name, requested) = split_spec(spec)
  println("Resolving " + name + " ...")
  // A name that is not on mooncakes.io is tried as a GitHub repository
  // (`owner/repo` or a URL) and installed from its releases.
  let manifest = fetch_manifest(name, requested) catch { _ => Json::null() }
  match manifest {
    Null => return install_github_tool(spec, bin_dir, force)
    _ => ()
  }
  let meta = match json_object(manifest, "metadata") {
    Some(m) => m
    None =>
      raise MbError("mooncakes.io returned no metadata for '" + name + "'")
  }
  let resolved_name = match json_string(meta, "name") {
    Some(n) => n
    None => name
  }
  let version = match json_string(meta, "version") {
    Some(v) => v
    None => raise MbError("could not determine a version for '" + name + "'")
  }
  let checksum = match json_string(meta, "checksum") {
    Some(c) => c
    None => raise MbError("could not determine a checksum for '" + name + "'")
  }
  let dir = tool_dir(resolved_name, version)
  if file_exists(path_join(dir, "tool.json")) && !force {
    println(
      resolved_name +
      " " +
      version +
      " is already installed; use --force to reinstall",
    )
    return
  }
  // Prefer a prebuilt binary from the module's GitHub release when one matches
  // this platform; otherwise fall through to building from source.
  let repository = match json_string(meta, "repository") {
    Some(r) => r
    None => ""
  }
  if repository != "" {
    let released = try_install_release(
      resolved_name, version, repository, requested, bin_dir,
    ) catch {
      e => {
        eprintln("warning: " + e.message() + "; building from source instead")
        None
      }
    }
    match released {
      Some(bins) => {
        let record : ToolMeta = {
          name: resolved_name,
          version,
          bins,
          bin: Some(bin_dir),
        }
        write_text(
          path_join(dir, "tool.json"),
          @json.to_json(record).stringify(indent=2),
        )
        println("Installed " + resolved_name + " " + version + " (prebuilt)")
        return
      }
      None => ()
    }
  }
  // Download and verify the source archive.
  let url = MOONCAKES_DOWNLOAD +
    "/user/" +
    resolved_name +
    "/" +
    version +
    ".zip"
  println("Downloading " + url + " ...")
  let zip_path = temp_path()
  download(url, zip_path, true)
  let actual = sha256_hex(read_bytes(zip_path))
  if actual != checksum {
    rm_rf(zip_path) catch {
      _ => ()
    }
    raise MbError("checksum mismatch for " + resolved_name + " " + version)
  }
  let src = path_join(dir, "src")
  rm_rf(src) catch {
    _ => ()
  }
  extract_zip(read_bytes(zip_path), src)
  rm_rf(zip_path) catch {
    _ => ()
  }
  // Build with a toolchain.
  let tc = resolve_toolchain(toolchain_override)
  println("Building " + resolved_name + " " + version + " ...")
  let built = build_tool(src, tc)
  // Install the binaries.
  mkdir_p(bin_dir)
  let installed : Array[String] = []
  for (tool_name, path) in built {
    let dest = path_join(bin_dir, tool_name)
    copy_file(path, dest)
    chmod_exec(dest)
    installed.push(tool_name)
    println("  installed " + dest)
  }
  let record : ToolMeta = {
    name: resolved_name,
    version,
    bins: installed,
    bin: Some(bin_dir),
  }
  write_text(
    path_join(dir, "tool.json"),
    @json.to_json(record).stringify(indent=2),
  )
  println("Installed " + resolved_name + " " + version)
}

///|
/// Read the metadata of every installed tool version.
pub fn installed_tools() -> Array[ToolMeta] raise MbError {
  let out : Array[ToolMeta] = []
  let root = tool_root()
  if !dir_exists(root) {
    return out
  }
  for key in list_dir(root) {
    let versions_dir = path_join(root, key)
    if !dir_exists(versions_dir) {
      continue
    }
    for version in list_dir(versions_dir) {
      let meta_path = path_join(path_join(versions_dir, version), "tool.json")
      if !file_exists(meta_path) {
        continue
      }
      let text = read_text(meta_path) catch { _ => continue }
      let meta : ToolMeta = @json.from_json(
        @json.parse(text) catch {
          _ => continue
        },
      ) catch {
        _ => continue
      }
      out.push(meta)
    }
  }
  out
}

///|
/// Where a tool's executables live: its recorded install directory, or the
/// current default for records written before that was tracked.
pub fn tool_bin_dir(meta : ToolMeta) -> String raise MbError {
  match meta.bin {
    Some(b) => b
    None => bin_dir()
  }
}

///|
/// The `mb tool list` command. With `outdated`, consult mooncakes.io and mark
/// tools that have a newer version available.
pub fn tool_list(outdated : Bool) -> Unit raise MbError {
  let tools = installed_tools()
  let root = tool_root()
  if tools.is_empty() {
    println("No tools installed (looked in " + root + ").")
    return
  }
  println("Installed tools in " + root + ":")
  for t in tools {
    let mut line = "  " + t.name + " " + t.version
    if outdated {
      let latest = latest_tool_version(t.name) catch { _ => "" }
      if latest == "" {
        line = line + "  (could not check for updates)"
      } else if latest != t.version {
        line = line + "  (newer: " + latest + ")"
      }
    }
    println(line)
    let bin = tool_bin_dir(t)
    if t.bins.is_empty() {
      println("    no binaries recorded")
    } else {
      let entries = t.bins.map(b => {
        if file_exists(path_join(bin, b)) {
          b
        } else {
          b + " (missing)"
        }
      })
      println("    " + entries.join(", ") + "  in " + bin)
    }
  }
}

///|
/// The `mb tool uninstall <module>` command.
pub fn tool_uninstall(spec : String) -> Unit raise MbError {
  let (name, requested) = split_spec(spec)
  let tools = installed_tools()
  let mut removed = false
  for t in tools {
    if t.name != name {
      continue
    }
    if requested is Some(v) && v != t.version {
      continue
    }
    // Remove from the directory the tool was actually installed into.
    let bin = tool_bin_dir(t)
    for b in t.bins {
      rm_rf(path_join(bin, b)) catch {
        _ => ()
      }
    }
    rm_rf(tool_dir(t.name, t.version)) catch {
      _ => ()
    }
    // Drop the per-tool directory once its last version is gone.
    let name_dir = path_join(tool_root(), tool_key(t.name))
    if dir_exists(name_dir) && list_dir_unsafe(name_dir).is_empty() {
      rm_rf(name_dir) catch {
        _ => ()
      }
    }
    println("Uninstalled " + t.name + " " + t.version)
    removed = true
  }
  if !removed {
    raise MbError("no installed tool matches '" + spec + "'")
  }
}

///|
/// The `mb tool upgrade` command. With `all`, upgrade every installed tool;
/// otherwise upgrade the named tools (any version specifier is ignored and the
/// latest version is installed). Each tool is rebuilt into the directory it was
/// originally installed into.
pub fn tool_upgrade(
  names : Array[String],
  all : Bool,
  toolchain_override : String,
) -> Unit raise MbError {
  ensure_tools()
  let tools = installed_tools()
  if tools.is_empty() {
    println("No tools installed.")
    return
  }
  let wanted : Array[ToolMeta] = []
  for t in tools {
    let mut pick = all
    for n in names {
      if fst(split_spec(n)) == t.name {
        pick = true
      }
    }
    if pick {
      // One entry per tool name, even when several versions are installed.
      let mut dup = false
      for w in wanted {
        if w.name == t.name {
          dup = true
        }
      }
      if !dup {
        wanted.push(t)
      }
    }
  }
  for t in wanted {
    let latest = latest_tool_version(t.name) catch {
      e => {
        eprintln("warning: could not check " + t.name + ": " + e.message())
        continue
      }
    }
    if latest == t.version {
      println(t.name + " " + t.version + " is already up to date")
    } else {
      println("Upgrading " + t.name + " " + t.version + " -> " + latest)
      tool_install(
        t.name + "@" + latest,
        toolchain_override,
        tool_bin_dir(t),
        true,
      )
      rm_rf(tool_dir(t.name, t.version)) catch {
        _ => ()
      }
    }
  }
  // Warn about names that matched no installed tool.
  for n in names {
    let name = fst(split_spec(n))
    let mut found = false
    for t in tools {
      if t.name == name {
        found = true
      }
    }
    if !found {
      eprintln("warning: '" + name + "' is not installed")
    }
  }
}

///|
/// The `mb tool uninstall` command: remove the named tools, or every installed
/// tool with `all`.
pub fn tool_uninstall_many(
  specs : Array[String],
  all : Bool,
) -> Unit raise MbError {
  if all {
    let tools = installed_tools()
    if tools.is_empty() {
      println("No tools installed.")
      return
    }
    let done : Array[String] = []
    for t in tools {
      let mut seen = false
      for d in done {
        if d == t.name {
          seen = true
        }
      }
      if seen {
        continue
      }
      done.push(t.name)
      tool_uninstall(t.name)
    }
    return
  }
  for s in specs {
    tool_uninstall(s)
  }
}

///|
fn fst(pair : (String, String?)) -> String {
  let (a, _) = pair
  a
}

///|
/// Latest published version of a module.
pub fn latest_tool_version(name : String) -> String raise MbError {
  let manifest = fetch_manifest(name, None)
  match json_string(manifest, "latest_version") {
    Some(v) => v
    None =>
      match json_object(manifest, "metadata") {
        Some(m) =>
          match json_string(m, "version") {
            Some(v) => v
            None =>
              raise MbError(
                "could not determine the latest version of '" + name + "'",
              )
          }
        None =>
          raise MbError(
            "could not determine the latest version of '" + name + "'",
          )
      }
  }
}
