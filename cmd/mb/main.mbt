///|
/// Entry point: parse arguments and hand off to the library.
fn main {
  let args = @env.args()
  let argv = if args.length() > 0 { args[1:].to_owned() } else { [] }
  let code = @lib.run_cli(argv) catch {
    e => {
      let code = e.exit_code()
      // A zero exit code is a deliberate stop (e.g. the user cancelled an
      // interactive prompt); it is not an error worth printing.
      if code != 0 {
        eprintln("mb: " + e.message())
      }
      code
    }
  }
  @lib.exit(code)
}
