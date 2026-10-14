///|
/// Entry point: parse arguments and hand off to the library.
fn main {
  let args = @env.args()
  let argv = if args.length() > 0 { args[1:].to_owned() } else { [] }
  let code = @lib.run_cli(argv) catch {
    e => {
      eprintln("mb: " + e.message())
      e.exit_code()
    }
  }
  @lib.exit(code)
}
