///|
/// Foreign function declarations backed by `native_stubs.c`.
///
/// The `mb` tool only targets native Linux/macOS builds, so these are the
/// only platform-specific bindings in the project.

///|
#borrow(cmd)
extern "C" fn mb_system(cmd : Bytes) -> Int32 = "mb_system"

///|
#borrow(cmd)
extern "C" fn mb_popen(cmd : Bytes) -> Bytes = "mb_popen"

///|
extern "C" fn mb_platform() -> Bytes = "mb_platform"

///|
#borrow(path)
extern "C" fn mb_chmod_exec(path : Bytes) -> Int32 = "mb_chmod_exec"

///|
extern "C" fn mb_isatty_stdout() -> Int32 = "mb_isatty_stdout"

///|
extern "C" fn mb_isatty_stdin() -> Int32 = "mb_isatty_stdin"

///|
#borrow(data)
extern "C" fn mb_write(data : Bytes) -> Int32 = "mb_write"

///|
extern "C" fn mb_tty_raw() -> Int32 = "mb_tty_raw"

///|
extern "C" fn mb_tty_restore() -> Int32 = "mb_tty_restore"

///|
extern "C" fn mb_read_byte(timeout_ms : Int32) -> Int32 = "mb_read_byte"

///|
extern "C" fn mb_read_line() -> Bytes = "mb_read_line"

///|
extern "C" fn mb_exit(code : Int32) -> Unit = "mb_exit"
