///|
/// Command-line parsing and dispatch for `mb`.
///
/// Argument handling mirrors `uv`: every command and subcommand responds to
/// `-h`/`--help` (which takes precedence over everything else), required
/// arguments and unknown options produce a clap-style usage error on stderr
/// with exit code 2, and `tool upgrade`/`tool uninstall` accept several names
/// or `--all`.

///|
pub const MB_VERSION : String = "0.2.1"

///|
fn tail(a : Array[String], from : Int32) -> Array[String] {
  a[from:].to_owned()
}

///|
/// Entry point used by `cmd/mb`. Returns the process exit code.
pub fn run_cli(argv : Array[String]) -> Int32 raise MbError {
  if argv.is_empty() {
    print_help()
    return 0
  }
  let rest = tail(argv, 1)
  match argv[0] {
    "run" => cli_run(rest)
    "moon" => cli_moon(rest)
    "tool" => cli_tool(rest)
    "env" => cli_env(rest)
    "help" => cli_help(rest)
    "version" | "--version" | "-V" => {
      println("mb " + MB_VERSION)
      0
    }
    "--help" | "-h" => {
      print_help()
      0
    }
    other => {
      eprintln("error: unrecognized command '" + other + "'")
      eprintln("")
      eprintln("Usage: mb <COMMAND>")
      eprintln("")
      eprintln("For more information, try '--help'.")
      2
    }
  }
}

///|
fn cli_help(rest : Array[String]) -> Int32 {
  match rest.get(0) {
    None => {
      print_help()
      0
    }
    Some(cmd) =>
      match cmd {
        "run" => {
          print_run_help()
          0
        }
        "moon" =>
          match rest.get(1) {
            None => {
              print_moon_help()
              0
            }
            Some(sub) => {
              print_moon_sub_help(sub)
              0
            }
          }
        "tool" =>
          match rest.get(1) {
            None => {
              print_tool_help()
              0
            }
            Some(sub) => {
              print_tool_sub_help(sub)
              0
            }
          }
        "env" =>
          match rest.get(1) {
            None => {
              print_env_help()
              0
            }
            Some(sub) => {
              print_env_sub_help(sub)
              0
            }
          }
        other => {
          eprintln("error: unrecognized command '" + other + "'")
          eprintln("")
          eprintln("For more information, try '--help'.")
          2
        }
      }
  }
}

///|
fn has_help_flag(args : Array[String]) -> Bool {
  for a in args {
    if a == "-h" || a == "--help" {
      return true
    }
  }
  false
}

///|
/// clap-style usage error: printed on stderr, exit code 2.
fn usage_error(msg : String, usage : String) -> Int32 {
  eprintln("error: " + msg)
  eprintln("")
  eprintln("Usage: " + usage)
  eprintln("")
  eprintln("For more information, try '--help'.")
  2
}

///|
fn unknown_subcommand(usage : String, sub : String) -> Int32 {
  eprintln("error: unrecognized subcommand '" + sub + "'")
  eprintln("")
  eprintln("Usage: " + usage)
  eprintln("")
  eprintln("For more information, try '--help'.")
  2
}

///|
fn print_help() -> Unit {
  let text =
    $|mb — a MoonBit toolchain and package manager
    $|
    $|Usage: mb [OPTIONS] <COMMAND>
    $|
    $|Commands:
    $|  run       Run a command inside a managed MoonBit environment
    $|  moon      Manage MoonBit toolchains
    $|  tool      Install, list, upgrade and remove tools from mooncakes.io
    $|  env       Manage .env files for the current project or globally
    $|
    $|Options:
    $|  -h, --help     Print help
    $|  -V, --version  Print version
    $|
    $|Environment:
    $|  MB_HOME      Data directory (default: ~/.local/share/mb)
    $|  MB_BIN_DIR   Where executables are installed (default: ~/.local/bin)
    $|  MB_ENV_KEY   Encryption key for .env values (default: ~/.mbenv)
  println(text)
}

///|
/// `mb run` — mirrors `uv run`: everything after the subcommand's own options
/// is passed straight through to the command.
fn cli_run(args : Array[String]) -> Int32 raise MbError {
  let mut moon = ""
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    if a == "--moon" && i + 1 < args.length() {
      moon = args[i + 1]
      i = i + 2
    } else if a.has_prefix("--moon=") {
      moon = a[7:].to_owned()
      i = i + 1
    } else if a == "-h" || a == "--help" {
      print_run_help()
      return 0
    } else {
      break
    }
  }
  cmd_run(moon, tail(args, i))
}

///|
fn print_run_help() -> Unit {
  let text =
    $|Run a command inside a managed MoonBit environment
    $|
    $|Usage: mb run [OPTIONS] <COMMAND> [ARGS]...
    $|
    $|Arguments:
    $|  <COMMAND>   The command to run
    $|  [ARGS]...   Arguments passed to the command
    $|
    $|Options:
    $|      --moon <VERSION>  Use the given managed MoonBit toolchain
    $|  -h, --help            Print help
  println(text)
}

///|
fn cli_moon(args : Array[String]) -> Int32 raise MbError {
  if args.is_empty() {
    print_moon_help()
    return 0
  }
  let sub = args[0]
  if sub == "-h" || sub == "--help" || sub == "help" {
    print_moon_help()
    return 0
  }
  let rest = tail(args, 1)
  if has_help_flag(rest) {
    print_moon_sub_help(sub)
    return 0
  }
  match sub {
    "list" | "ls" =>
      if !rest.is_empty() {
        usage_error("unexpected argument '" + rest[0] + "'", "mb moon list")
      } else {
        moon_list()
        0
      }
    "install" | "add" | "i" =>
      match parse_version_flags(rest, "latest") {
        Err(e) => usage_error(e, "mb moon install [OPTIONS] [VERSION]")
        Ok((version, force)) => {
          moon_install(version, force)
          0
        }
      }
    "uninstall" | "remove" | "rm" =>
      match parse_required_arg(rest, "<VERSION>") {
        Err(e) => usage_error(e, "mb moon uninstall <VERSION>")
        Ok(version) => {
          moon_uninstall(version)
          0
        }
      }
    "default" | "use" =>
      match parse_required_arg(rest, "<VERSION>") {
        Err(e) => usage_error(e, "mb moon default <VERSION>")
        Ok(version) => {
          moon_set_default(version)
          0
        }
      }
    "which" => {
      let version = if rest.is_empty() {
        ""
      } else {
        match parse_required_arg(rest, "<VERSION>") {
          Err(e) => return usage_error(e, "mb moon which [VERSION]")
          Ok(v) => v
        }
      }
      moon_which(version)
      0
    }
    "latest" =>
      if !rest.is_empty() {
        usage_error("unexpected argument '" + rest[0] + "'", "mb moon latest")
      } else {
        match latest_moon_cli_version() {
          Some(v) => {
            println(v)
            0
          }
          None =>
            raise MbError("could not determine the latest MoonBit version")
        }
      }
    other => unknown_subcommand("mb moon <COMMAND>", other)
  }
}

///|
fn print_moon_help() -> Unit {
  let text =
    $|Manage MoonBit toolchains
    $|
    $|Usage: mb moon [OPTIONS] <COMMAND>
    $|
    $|Commands:
    $|  list (ls)                List installed and available toolchains
    $|  install (add, i)         Install a MoonBit toolchain
    $|  uninstall (remove, rm)   Remove an installed toolchain
    $|  default                  Set the default toolchain
    $|  which                    Print the path to a toolchain's `moon`
    $|  latest                   Print the latest published toolchain version
    $|
    $|Options:
    $|  -h, --help  Print help
  println(text)
}

///|
fn print_moon_sub_help(sub : String) -> Unit {
  match sub {
    "list" | "ls" => print_moon_list_help()
    "install" | "add" | "i" => print_moon_install_help()
    "uninstall" | "remove" | "rm" => print_moon_uninstall_help()
    "default" | "use" => print_moon_default_help()
    "which" => print_moon_which_help()
    "latest" => print_moon_latest_help()
    _ => print_moon_help()
  }
}

///|
fn print_moon_list_help() -> Unit {
  let text =
    $|List installed MoonBit toolchains and the release channel
    $|
    $|Usage: mb moon list
    $|
    $|Options:
    $|  -h, --help  Print help
  println(text)
}

///|
fn print_moon_install_help() -> Unit {
  let text =
    $|Install a MoonBit toolchain
    $|
    $|Usage: mb moon install [OPTIONS] [VERSION]
    $|
    $|Arguments:
    $|  [VERSION]  Version to install (default: latest)
    $|
    $|Options:
    $|  -f, --force  Reinstall even if already installed
    $|  -h, --help   Print help
  println(text)
}

///|
fn print_moon_uninstall_help() -> Unit {
  let text =
    $|Remove an installed MoonBit toolchain
    $|
    $|Usage: mb moon uninstall <VERSION>
    $|
    $|Arguments:
    $|  <VERSION>  The toolchain version to remove, e.g. 0.10.14
    $|
    $|Options:
    $|  -h, --help  Print help
  println(text)
}

///|
fn print_moon_default_help() -> Unit {
  let text =
    $|Set the default MoonBit toolchain
    $|
    $|Usage: mb moon default <VERSION>
    $|
    $|Arguments:
    $|  <VERSION>  Toolchain version to select, e.g. 0.10.14
    $|
    $|Options:
    $|  -h, --help  Print help
  println(text)
}

///|
fn print_moon_which_help() -> Unit {
  let text =
    $|Print the path to a toolchain's `moon` executable
    $|
    $|Usage: mb moon which [VERSION]
    $|
    $|Arguments:
    $|  [VERSION]  Toolchain version to inspect (default: active)
    $|
    $|Options:
    $|  -h, --help  Print help
  println(text)
}

///|
fn print_moon_latest_help() -> Unit {
  let text =
    $|Print the latest published MoonBit toolchain version
    $|
    $|Usage: mb moon latest
    $|
    $|Options:
    $|  -h, --help  Print help
  println(text)
}

///|
fn cli_tool(args : Array[String]) -> Int32 raise MbError {
  if args.is_empty() {
    print_tool_help()
    return 0
  }
  let sub = args[0]
  if sub == "-h" || sub == "--help" || sub == "help" {
    print_tool_help()
    return 0
  }
  let rest = tail(args, 1)
  if has_help_flag(rest) {
    print_tool_sub_help(sub)
    return 0
  }
  match sub {
    "install" | "add" | "i" =>
      match parse_tool_install_flags(rest) {
        Err(e) => usage_error(e, "mb tool install [OPTIONS] <NAME>[@<VERSION>]")
        Ok(opt) => {
          tool_install(opt.spec, opt.moon, opt.bin, opt.force, opt.interactive)
          0
        }
      }
    "upgrade" | "update" | "up" =>
      match parse_names_flags(rest) {
        Err(e) => usage_error(e, "mb tool upgrade [OPTIONS] <NAME>...")
        Ok(o) => {
          tool_upgrade(o.names, o.all, o.moon)
          0
        }
      }
    "list" | "ls" =>
      match parse_list_flags(rest) {
        Err(e) => usage_error(e, "mb tool list [OPTIONS]")
        Ok(outdated) => {
          tool_list(outdated)
          0
        }
      }
    "uninstall" | "remove" | "rm" =>
      match parse_names_flags(rest) {
        Err(e) => usage_error(e, "mb tool uninstall [OPTIONS] <NAME>...")
        Ok(o) => {
          tool_uninstall_many(o.names, o.all)
          0
        }
      }
    other => unknown_subcommand("mb tool <COMMAND>", other)
  }
}

///|
fn print_tool_help() -> Unit {
  let text =
    $|Install, list, upgrade and remove tools from mooncakes.io
    $|
    $|Usage: mb tool [OPTIONS] <COMMAND>
    $|
    $|Commands:
    $|  install (add, i)           Install a tool from a mooncakes.io module
    $|  upgrade (update, up)       Upgrade installed tools to their latest version
    $|  list (ls)                  List installed tools
    $|  uninstall (remove, rm)     Remove an installed tool
    $|
    $|Options:
    $|  -h, --help  Print help
  println(text)
}

///|
fn print_tool_sub_help(sub : String) -> Unit {
  match sub {
    "install" | "add" | "i" => print_tool_install_help()
    "upgrade" | "update" | "up" => print_tool_upgrade_help()
    "list" | "ls" => print_tool_list_help()
    "uninstall" | "remove" | "rm" => print_tool_uninstall_help()
    _ => print_tool_help()
  }
}

///|
fn print_tool_install_help() -> Unit {
  let text =
    $|Install a tool from a mooncakes.io module
    $|
    $|Usage: mb tool install [OPTIONS] <NAME>[@<VERSION>]
    $|
    $|Arguments:
    $|  <NAME>[@<VERSION>]  The package to install, e.g. author/module or
    $|                      author/module@0.1.1
    $|
    $|Options:
    $|  -f, --force          Force (re)installation even if already installed
    $|  -i, --interactive    Choose which executables to install (esc cancels)
    $|      --bin <DIR>      Install executables into DIR (default: ~/.local/bin)
    $|      --bin-dir <DIR>  Alias for --bin
    $|      --moon <VERSION> Build with the given managed MoonBit toolchain
    $|  -h, --help           Print help
  println(text)
}

///|
fn print_tool_upgrade_help() -> Unit {
  let text =
    $|Upgrade installed tools to their latest version
    $|
    $|Usage: mb tool upgrade [OPTIONS] <NAME>...
    $|
    $|Arguments:
    $|  <NAME>...  Name of a tool to upgrade, with an optional version
    $|             specifier; pass --all to upgrade every installed tool
    $|
    $|Options:
    $|      --all                Upgrade all installed tools
    $|      --moon <VERSION>     Build with the given managed MoonBit toolchain
    $|  -h, --help               Print help
  println(text)
}

///|
fn print_tool_list_help() -> Unit {
  let text =
    $|List installed tools
    $|
    $|Usage: mb tool list [OPTIONS]
    $|
    $|Options:
    $|      --outdated  Check mooncakes.io and mark tools that have a newer version
    $|  -h, --help      Print help
  println(text)
}

///|
fn print_tool_uninstall_help() -> Unit {
  let text =
    $|Remove an installed tool
    $|
    $|Usage: mb tool uninstall [OPTIONS] <NAME>...
    $|
    $|Arguments:
    $|  <NAME>...  Name of the tool to remove
    $|
    $|Options:
    $|      --all    Uninstall all installed tools
    $|  -h, --help   Print help
  println(text)
}

///|
fn cli_env(args : Array[String]) -> Int32 raise MbError {
  if args.is_empty() {
    print_env_help()
    return 0
  }
  let sub = args[0]
  if sub == "-h" || sub == "--help" || sub == "help" {
    print_env_help()
    return 0
  }
  let rest = tail(args, 1)
  if has_help_flag(rest) {
    print_env_sub_help(sub)
    return 0
  }
  match sub {
    "set" | "add" =>
      match parse_env_set_flags(rest) {
        Err(e) => usage_error(e, "mb env set [OPTIONS] <KEY>=<VALUE>")
        Ok(o) => {
          env_set(o.key, o.value, o.global, o.plain)
          0
        }
      }
    "rm" | "remove" | "unset" =>
      match parse_env_names_flags(rest) {
        Err(e) => usage_error(e, "mb env rm [OPTIONS] <KEY>...")
        Ok((keys, global)) => {
          env_rm(keys, global)
          0
        }
      }
    "list" | "ls" =>
      match parse_env_list_flags(rest) {
        Err(e) => usage_error(e, "mb env list [OPTIONS]")
        Ok((global, mask)) => {
          env_list(global, mask)
          0
        }
      }
    other => unknown_subcommand("mb env <COMMAND>", other)
  }
}

///|
fn print_env_help() -> Unit {
  let text =
    $|Manage .env files for the current project or globally
    $|
    $|Usage: mb env [OPTIONS] <COMMAND>
    $|
    $|Commands:
    $|  set          Set a variable (encrypted by default)
    $|  rm           Remove one or more variables
    $|  list (ls)    List the variables (encrypted values are masked)
    $|
    $|Options:
    $|  -h, --help  Print help
  println(text)
}

///|
fn print_env_sub_help(sub : String) -> Unit {
  match sub {
    "set" | "add" => print_env_set_help()
    "rm" | "remove" | "unset" => print_env_rm_help()
    "list" | "ls" => print_env_list_help()
    _ => print_env_help()
  }
}

///|
fn print_env_set_help() -> Unit {
  let text =
    $|Set a variable in .env (or the global ~/.mbenv)
    $|
    $|Usage: mb env set [OPTIONS] <KEY>=<VALUE>
    $|       mb env set [OPTIONS] <KEY> <VALUE>
    $|
    $|Arguments:
    $|  <KEY>    The variable name
    $|  <VALUE>  The value; encrypted by default
    $|
    $|Options:
    $|  -g, --global  Write to ~/.mbenv instead of ./.env
    $|      --plain   Store the value in plaintext
    $|  -h, --help    Print help
  println(text)
}

///|
fn print_env_rm_help() -> Unit {
  let text =
    $|Remove one or more variables from .env (or the global ~/.mbenv)
    $|
    $|Usage: mb env rm [OPTIONS] <KEY>...
    $|
    $|Arguments:
    $|  <KEY>...  The variable name(s) to remove
    $|
    $|Options:
    $|  -g, --global  Operate on ~/.mbenv instead of ./.env
    $|  -h, --help    Print help
  println(text)
}

///|
fn print_env_list_help() -> Unit {
  let text =
    $|List the variables in .env (or the global ~/.mbenv)
    $|
    $|Encrypted values are shown in clear only when stdout is a terminal;
    $|otherwise they are masked as <encrypted>.
    $|
    $|Usage: mb env list [OPTIONS]
    $|
    $|Options:
    $|  -g, --global  Operate on ~/.mbenv instead of ./.env
    $|      --mask    Always mask encrypted values
    $|  -h, --help    Print help
  println(text)
}

///|
priv struct EnvSetOpts {
  key : String
  value : String
  global : Bool
  plain : Bool
}

///|
fn parse_env_set_flags(args : Array[String]) -> Result[EnvSetOpts, String] {
  let mut global = false
  let mut plain = false
  let pos : Array[String] = []
  for a in args {
    if a == "--global" || a == "-g" {
      global = true
    } else if a == "--plain" {
      plain = true
    } else if a.has_prefix("-") && a != "-" {
      return Err("unexpected option '" + a + "'")
    } else {
      pos.push(a)
    }
  }
  let (key, value) = if pos.length() == 1 {
    match pos[0].find("=") {
      Some(i) =>
        if i == 0 {
          return Err("invalid assignment '" + pos[0] + "': empty key")
        } else {
          (pos[0][:i].to_owned(), pos[0][i + 1:].to_owned())
        }
      None =>
        return Err(
          "invalid assignment '" + pos[0] + "': expected <KEY>=<VALUE>",
        )
    }
  } else if pos.length() == 2 {
    (pos[0], pos[1])
  } else if pos.is_empty() {
    return Err(
      "the following required arguments were not provided:\n  <KEY>=<VALUE>",
    )
  } else {
    return Err("unexpected argument '" + pos[2] + "'")
  }
  if key == "" {
    return Err("the key must not be empty")
  }
  Ok({ key, value, global, plain, })
}

///|
fn parse_env_names_flags(
  args : Array[String],
) -> Result[(Array[String], Bool), String] {
  let keys : Array[String] = []
  let mut global = false
  for a in args {
    if a == "--global" || a == "-g" {
      global = true
    } else if a.has_prefix("-") && a != "-" {
      return Err("unexpected option '" + a + "'")
    } else {
      keys.push(a)
    }
  }
  if keys.is_empty() {
    return Err("the following required argument was not provided:\n  <KEY>...")
  }
  Ok((keys, global))
}

///|
fn parse_env_list_flags(args : Array[String]) -> Result[(Bool, Bool), String] {
  let mut global = false
  let mut mask = false
  for a in args {
    if a == "--global" || a == "-g" {
      global = true
    } else if a == "--mask" {
      mask = true
    } else if a.has_prefix("-") && a != "-" {
      return Err("unexpected option '" + a + "'")
    } else {
      return Err("unexpected argument '" + a + "'")
    }
  }
  Ok((global, mask))
}

///|
/// Parse the shared `--all` / `--moon` / `<NAME>...` option set used by
/// `tool upgrade` and `tool uninstall`.
fn parse_names_flags(args : Array[String]) -> Result[NamesFlags, String] {
  let names : Array[String] = []
  let mut all = false
  let mut moon = ""
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    if a == "--all" {
      all = true
      i = i + 1
    } else if a == "--moon" && i + 1 < args.length() {
      moon = args[i + 1]
      i = i + 2
    } else if a.has_prefix("--moon=") {
      moon = a[7:].to_owned()
      i = i + 1
    } else if a.has_prefix("-") {
      return Err("unexpected option '" + a + "'")
    } else {
      names.push(a)
      i = i + 1
    }
  }
  if names.is_empty() && !all {
    return Err(
      "the following required arguments were not provided:\n  <NAME>...",
    )
  }
  Ok({ names, all, moon, })
}

///|
priv struct NamesFlags {
  names : Array[String]
  all : Bool
  moon : String
}

///|
fn parse_list_flags(args : Array[String]) -> Result[Bool, String] {
  let mut outdated = false
  for a in args {
    if a == "--outdated" {
      outdated = true
    } else if a.has_prefix("-") {
      return Err("unexpected option '" + a + "'")
    } else {
      return Err("unexpected argument '" + a + "'")
    }
  }
  Ok(outdated)
}

///|
/// A single required value, with no extra flags (which are filtered out by the
/// `--help` check before this runs).
fn parse_required_arg(
  args : Array[String],
  placeholder : String,
) -> Result[String, String] {
  if args.is_empty() {
    Err("the following required argument was not provided:\n  " + placeholder)
  } else if args.length() > 1 {
    Err("unexpected argument '" + args[1] + "'")
  } else {
    Ok(args[0])
  }
}

///|
/// Parsed flags for `mb tool install`.
pub struct ToolInstallOpts {
  spec : String
  force : Bool
  bin : String
  moon : String
  interactive : Bool
}

///|
fn parse_tool_install_flags(
  args : Array[String],
) -> Result[ToolInstallOpts, String] {
  let mut spec = ""
  let mut force = false
  let mut bin = ""
  let mut moon = ""
  let mut interactive = false
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    if a == "--force" || a == "-f" {
      force = true
      i = i + 1
    } else if a == "--interactive" || a == "-i" {
      interactive = true
      i = i + 1
    } else if a == "--bin" || a == "--bin-dir" {
      if i + 1 >= args.length() {
        return Err(
          "a value is required for '" + a + " <DIR>' but none was supplied",
        )
      }
      bin = args[i + 1]
      i = i + 2
    } else if a.has_prefix("--bin-dir=") {
      bin = a[10:].to_owned()
      i = i + 1
    } else if a.has_prefix("--bin=") {
      bin = a[6:].to_owned()
      i = i + 1
    } else if a == "--moon" {
      if i + 1 >= args.length() {
        return Err(
          "a value is required for '--moon <VERSION>' but none was supplied",
        )
      }
      moon = args[i + 1]
      i = i + 2
    } else if a.has_prefix("--moon=") {
      moon = a[7:].to_owned()
      i = i + 1
    } else if a.has_prefix("-") {
      return Err("unexpected option '" + a + "'")
    } else if spec == "" {
      spec = a
      i = i + 1
    } else {
      return Err("unexpected argument '" + a + "'")
    }
  }
  if spec == "" {
    return Err("the following required argument was not provided:\n  <NAME>")
  }
  Ok({ spec, force, bin, moon, interactive, })
}

///|
fn parse_version_flags(
  args : Array[String],
  default_version : String,
) -> Result[(String, Bool), String] {
  let mut version = default_version
  let mut force = false
  let mut seen = false
  for a in args {
    if a == "--force" || a == "-f" || a == "--force-reinstall" {
      force = true
    } else if a.has_prefix("-") {
      return Err("unexpected option '" + a + "'")
    } else if !seen {
      version = a
      seen = true
    } else {
      return Err("unexpected argument '" + a + "'")
    }
  }
  Ok((version, force))
}
