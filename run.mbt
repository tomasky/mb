///|
/// The `mb run` command: execute a program inside a managed MoonBit
/// environment, mirroring `uv run`.

///|
/// Run `cmd` with the toolchain environment. Returns the child exit code.
pub fn cmd_run(moon_version : String, cmd : Array[String]) -> Int raise MbError {
  if cmd.is_empty() {
    raise MbError("usage: mb run [--moon <version>] <command> [args...]")
  }
  // Export `.env`/`.mbenv` from the current directory and the global
  // `~/.mbenv`; later files win and children inherit the result. The global
  // file is skipped when `HOME` is unavailable.
  let global = global_env_file() catch { _ => "" }
  let paths = if global == "" {
    [".mbenv", ".env"]
  } else {
    [global, ".mbenv", ".env"]
  }
  apply_dotenv(paths)
  let env = if moon_version != "" {
    Some(resolve_toolchain(moon_version))
  } else {
    match effective_toolchain() {
      Some(v) =>
        Some({
          moon: path_join(toolchain_dir(v), "bin/moon"),
          home: Some(toolchain_dir(v)),
          bin: Some(path_join(toolchain_dir(v), "bin")),
        })
      None => None
    }
  }
  let mut full = match env {
    Some(tc) => env_prefix(tc)
    None => ""
  }
  for i, arg in cmd {
    if i > 0 {
      full = full + " "
    }
    full = full + shell_quote(arg)
  }
  run_status(full)
}

///|
/// Terminate the process with `code`.
pub fn exit(code : Int) -> Unit {
  mb_exit(code)
}
