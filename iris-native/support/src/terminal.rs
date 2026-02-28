use libc::{self, c_int, termios, winsize};
use std::mem::MaybeUninit;

static mut ORIGINAL_TERMIOS: Option<termios> = None;

/// Enter raw mode on stdin. Saves original termios for later restore.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn iris_terminal_enter_raw() -> c_int {
    let mut orig = MaybeUninit::<termios>::uninit();
    if libc::tcgetattr(libc::STDIN_FILENO, orig.as_mut_ptr()) != 0 {
        return -1;
    }
    let orig = orig.assume_init();
    ORIGINAL_TERMIOS = Some(orig);

    let mut raw = orig;
    libc::cfmakeraw(&mut raw);
    libc::tcsetattr(libc::STDIN_FILENO, libc::TCSAFLUSH, &raw)
}

/// Restore original terminal mode. Returns 0 on success, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn iris_terminal_restore() -> c_int {
    match ORIGINAL_TERMIOS {
        Some(ref orig) => libc::tcsetattr(libc::STDIN_FILENO, libc::TCSAFLUSH, orig),
        None => -1,
    }
}

/// Get terminal columns. Returns 0 on error.
#[no_mangle]
pub unsafe extern "C" fn iris_terminal_get_cols() -> u16 {
    let mut ws = MaybeUninit::<winsize>::uninit();
    if libc::ioctl(libc::STDOUT_FILENO, libc::TIOCGWINSZ, ws.as_mut_ptr()) != 0 {
        return 0;
    }
    ws.assume_init().ws_col
}

/// Get terminal rows. Returns 0 on error.
#[no_mangle]
pub unsafe extern "C" fn iris_terminal_get_rows() -> u16 {
    let mut ws = MaybeUninit::<winsize>::uninit();
    if libc::ioctl(libc::STDOUT_FILENO, libc::TIOCGWINSZ, ws.as_mut_ptr()) != 0 {
        return 0;
    }
    ws.assume_init().ws_row
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_terminal_size() {
        unsafe {
            // These may return 0 in CI (no tty), but should not crash
            let cols = iris_terminal_get_cols();
            let rows = iris_terminal_get_rows();
            // In a real terminal both should be > 0; in CI they may be 0
            assert!(cols == 0 || cols > 0);
            assert!(rows == 0 || rows > 0);
        }
    }

    #[test]
    fn test_restore_without_enter_returns_error() {
        unsafe {
            ORIGINAL_TERMIOS = None;
            let rc = iris_terminal_restore();
            assert_eq!(rc, -1, "restore without enter should fail");
        }
    }
}
