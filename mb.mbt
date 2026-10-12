///|
/// `mb` — a MoonBit-native toolchain and package manager.
///
/// The public API is split across a few files:
///
/// - `error.mbt`      — the single `MbError` type.
/// - `util.mbt`       — paths, filesystem, processes and hashing.
/// - `native_stubs.*` — the small libc FFI layer.
/// - `http.mbt`       — downloads via the system `curl`.
/// - `archive.mbt`    — zip and tar.gz extraction.
/// - `json_util.mbt`  — JSON accessors.
/// - `moon.mbt`       — `mb moon` (toolchain management).
/// - `tool.mbt`       — `mb tool` (mooncakes.io tool installs).
/// - `run.mbt`        — `mb run`.
/// - `cli.mbt`        — argument parsing and dispatch.
