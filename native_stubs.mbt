///|
/// Foreign function declarations backed by `native_stubs.c`.
///
/// The `mb` tool only targets native Linux/macOS builds, so these are the
/// only platform-specific bindings in the project.

///|
#borrow(cmd)
extern "C" fn mb_system(cmd : Bytes) -> Int = "mb_system"

///|
#borrow(cmd)
extern "C" fn mb_popen(cmd : Bytes) -> Bytes = "mb_popen"

///|
extern "C" fn mb_platform() -> Bytes = "mb_platform"

///|
#borrow(path)
extern "C" fn mb_chmod_exec(path : Bytes) -> Int = "mb_chmod_exec"

///|
extern "C" fn mb_isatty_stdout() -> Int = "mb_isatty_stdout"

///|
extern "C" fn mb_read_line() -> Bytes = "mb_read_line"

///|
extern "C" fn mb_exit(code : Int) -> Unit = "mb_exit"
