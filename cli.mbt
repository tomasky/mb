///|
/// Command-line parsing and dispatch for `mb`.

///|
pub const MB_VERSION : String = "0.1.1"

///|
fn tail(a : Array[String], from : Int) -> Array[String] {
  a[from:].to_owned()
}

///|
/// Entry point used by `cmd/main`. Returns the process exit code.
pub fn run_cli(argv : Array[String]) -> Int raise MbError {
  if argv.is_empty() {
    print_help()
    return 0
  }
  let rest = tail(argv, 1)
  match argv[0] {
    "run" => cli_run(rest)
    "moon" => cli_moon(rest)
    "tool" => cli_tool(rest)
    "help" | "--help" | "-h" => {
      print_help()
      0
    }
    "version" | "--version" | "-V" => {
      println("mb " + MB_VERSION)
      0
    }
    other => {
      eprintln("mb: unknown command '" + other + "'")
      print_help()
      2
    }
  }
}

///|
fn print_help() -> Unit {
  let text =
    $|mb — a MoonBit toolchain and package manager
    $|
    $|Usage: mb <command> [options]
    $|
    $|Commands:
    $|  run [--moon <version>] <command> [args...]
    $|        Run a command inside a managed MoonBit environment.
    $|
    $|  moon list                 List installed and available toolchains.
    $|  moon install [version]    Install a MoonBit toolchain (default: latest).
    $|  moon uninstall <version>  Remove an installed toolchain.
    $|  moon default <version>    Set the default toolchain.
    $|  moon which [version]      Print the path to a toolchain's `moon`.
    $|
    $|  tool install <name>[@<version>] [--force] [--bin <dir>] [--moon <version>]
    $|        Download a mooncakes.io module, build it and install its binaries.
    $|  tool list                 List installed tools.
    $|  tool upgrade [name]       Upgrade installed tools to their latest version.
    $|  tool uninstall <name>     Remove an installed tool.
    $|
    $|Environment:
    $|  MB_HOME      Data directory (default: ~/.local/share/mb).
    $|  MB_BIN_DIR   Where executables are installed (default: ~/.local/bin).
    $|
    $|Options:
    $|  -h, --help       Show this help.
    $|  -V, --version    Show the version.
  println(text)
}

///|
fn cli_run(args : Array[String]) -> Int raise MbError {
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
    } else {
      break
    }
  }
  cmd_run(moon, tail(args, i))
}

///|
fn cli_moon(args : Array[String]) -> Int raise MbError {
  if args.is_empty() {
    raise MbError("usage: mb moon <list|install|uninstall|default|which> [...]")
  }
  let sub = args[0]
  let rest = tail(args, 1)
  match sub {
    "list" | "ls" => {
      moon_list()
      0
    }
    "install" | "add" => {
      let (version, force) = parse_version_flags(rest, "latest")
      moon_install(version, force)
      0
    }
    "uninstall" | "remove" | "rm" => {
      let version = match rest.get(0) {
        Some(v) => v
        None => raise MbError("usage: mb moon uninstall <version>")
      }
      moon_uninstall(version)
      0
    }
    "default" | "use" => {
      let version = match rest.get(0) {
        Some(v) => v
        None => raise MbError("usage: mb moon default <version>")
      }
      moon_set_default(version)
      0
    }
    "which" => {
      moon_which(
        match rest.get(0) {
          Some(v) => v
          None => ""
        },
      )
      0
    }
    "latest" => {
      match latest_moon_cli_version() {
        Some(v) => println(v)
        None => raise MbError("could not determine the latest MoonBit version")
      }
      0
    }
    other => raise MbError("unknown `moon` subcommand: " + other)
  }
}

///|
fn parse_version_flags(
  args : Array[String],
  default_version : String,
) -> (String, Bool) raise MbError {
  let mut version = default_version
  let mut force = false
  let mut seen = false
  for a in args {
    if a == "--force" || a == "-f" {
      force = true
    } else if a == "--force-reinstall" {
      force = true
    } else if a.has_prefix("-") {
      raise MbError("unexpected option: " + a)
    } else if !seen {
      version = a
      seen = true
    } else {
      raise MbError("unexpected argument: " + a)
    }
  }
  (version, force)
}

///|
fn cli_tool(args : Array[String]) -> Int raise MbError {
  if args.is_empty() {
    raise MbError("usage: mb tool <install|list|upgrade|uninstall> [...]")
  }
  let sub = args[0]
  let rest = tail(args, 1)
  match sub {
    "install" | "add" => {
      let opt = parse_tool_flags(rest, true)
      tool_install(opt.spec, opt.moon, opt.bin, opt.force)
      0
    }
    "upgrade" | "update" | "up" => {
      let opt = parse_tool_flags(rest, false)
      tool_upgrade(opt.spec, opt.moon, opt.bin)
      0
    }
    "list" | "ls" => {
      tool_list()
      0
    }
    "uninstall" | "remove" | "rm" => {
      let opt = parse_tool_flags(rest, true)
      tool_uninstall(opt.spec)
      0
    }
    other => raise MbError("unknown `tool` subcommand: " + other)
  }
}

///|
/// Parsed `mb tool` flags.
pub struct ToolFlags {
  spec : String
  force : Bool
  bin : String
  moon : String
}

///|
fn parse_tool_flags(
  args : Array[String],
  require_spec : Bool,
) -> ToolFlags raise MbError {
  let mut spec = ""
  let mut force = false
  let mut bin = ""
  let mut moon = ""
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    if a == "--force" || a == "-f" {
      force = true
      i = i + 1
    } else if a == "--bin" && i + 1 < args.length() {
      bin = args[i + 1]
      i = i + 2
    } else if a.has_prefix("--bin=") {
      bin = a[6:].to_owned()
      i = i + 1
    } else if a == "--moon" && i + 1 < args.length() {
      moon = args[i + 1]
      i = i + 2
    } else if a.has_prefix("--moon=") {
      moon = a[7:].to_owned()
      i = i + 1
    } else if a.has_prefix("-") {
      raise MbError("unexpected option: " + a)
    } else if spec == "" {
      spec = a
      i = i + 1
    } else {
      raise MbError("unexpected argument: " + a)
    }
  }
  if require_spec && spec == "" {
    raise MbError("usage: mb tool install <author>/<module>[@<version>]")
  }
  { spec, force, bin, moon, }
}
