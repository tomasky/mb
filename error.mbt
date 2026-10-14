///|
/// The single error type surfaced by the `mb` library. Every fallible helper
/// converts lower-level failures into this so the CLI can print one clean
/// message and exit non-zero.
pub(all) suberror MbError {
  MbError(String)
  /// A failure that must exit with a specific status, mirroring uv (which
  /// exits 2, for example, when an executable would be clobbered).
  Coded(String, Int)
}

///|
pub fn MbError::message(self : MbError) -> String {
  match self {
    MbError(msg) => msg
    Coded(msg, _) => msg
  }
}

///|
/// Process exit status the CLI should use for this error.
pub fn MbError::exit_code(self : MbError) -> Int {
  match self {
    MbError(_) => 1
    Coded(_, code) => code
  }
}

///|
/// Abort the current operation with a human-readable message.
pub fn fail(msg : String) -> Unit raise MbError {
  raise MbError(msg)
}
