///|
/// The single error type surfaced by the `mb` library. Every fallible helper
/// converts lower-level failures into this so the CLI can print one clean
/// message and exit non-zero.
pub(all) suberror MbError {
  MbError(String)
}

///|
pub fn MbError::message(self : MbError) -> String {
  let MbError(msg) = self
  msg
}

///|
/// Abort the current operation with a human-readable message.
pub fn fail(msg : String) -> Unit raise MbError {
  raise MbError(msg)
}
