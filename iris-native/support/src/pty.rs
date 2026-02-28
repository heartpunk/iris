use libc::{self, c_char, c_int, pid_t, winsize};
use std::ffi::CString;
use std::ptr;

static mut LAST_MASTER_FD: c_int = -1;
static mut LAST_CHILD_PID: pid_t = -1;

/// Fork a PTY with the given dimensions, exec $SHELL in the child.
/// Returns 0 on success, -1 on error. Use iris_forkpty_master/pid to get results.
#[no_mangle]
pub unsafe extern "C" fn iris_forkpty(cols: u16, rows: u16) -> c_int {
    let mut ws = winsize {
        ws_col: cols,
        ws_row: rows,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };

    let mut master_fd: c_int = -1;
    let pid = libc::forkpty(&mut master_fd, ptr::null_mut(), ptr::null_mut(), &mut ws);

    if pid < 0 {
        LAST_MASTER_FD = -1;
        LAST_CHILD_PID = -1;
        return -1;
    }

    if pid == 0 {
        // Child: exec $SHELL
        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string());
        let c_shell =
            CString::new(shell.as_str()).unwrap_or_else(|_| CString::new("/bin/sh").unwrap());
        let argv: [*const c_char; 2] = [c_shell.as_ptr(), ptr::null()];
        libc::execvp(c_shell.as_ptr(), argv.as_ptr());
        libc::_exit(1);
    }

    LAST_MASTER_FD = master_fd;
    LAST_CHILD_PID = pid;
    0
}

/// Get master fd from last successful iris_forkpty call.
#[no_mangle]
pub unsafe extern "C" fn iris_forkpty_master() -> c_int {
    LAST_MASTER_FD
}

/// Get child pid from last successful iris_forkpty call.
#[no_mangle]
pub unsafe extern "C" fn iris_forkpty_pid() -> c_int {
    LAST_CHILD_PID as c_int
}

/// Read from a PTY master fd into buf. Returns bytes read, 0 on EOF, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn iris_pty_read(fd: c_int, buf: *mut u8, len: usize) -> isize {
    libc::read(fd, buf as *mut libc::c_void, len)
}

/// Write to a PTY master fd. Returns bytes written, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn iris_pty_write(fd: c_int, buf: *const u8, len: usize) -> isize {
    libc::write(fd, buf as *const libc::c_void, len)
}

/// Resize a PTY. Returns 0 on success, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn iris_pty_resize(fd: c_int, cols: u16, rows: u16) -> c_int {
    let ws = winsize {
        ws_col: cols,
        ws_row: rows,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    libc::ioctl(fd, libc::TIOCSWINSZ, &ws)
}

/// Close a PTY master fd.
#[no_mangle]
pub unsafe extern "C" fn iris_pty_close(fd: c_int) -> c_int {
    libc::close(fd)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_forkpty_returns_valid_fds() {
        unsafe {
            let rc = iris_forkpty(80, 24);
            assert_eq!(rc, 0, "forkpty should succeed");

            let master = iris_forkpty_master();
            let pid = iris_forkpty_pid();
            assert!(master >= 0, "master_fd should be non-negative");
            assert!(pid > 0, "child_pid should be positive");

            libc::kill(pid, libc::SIGTERM);
            iris_pty_close(master);
            libc::waitpid(pid, ptr::null_mut(), 0);
        }
    }

    #[test]
    fn test_pty_write_read_roundtrip() {
        unsafe {
            let rc = iris_forkpty(80, 24);
            assert_eq!(rc, 0);
            let master = iris_forkpty_master();
            let pid = iris_forkpty_pid();

            libc::usleep(50_000);

            let msg = b"echo hello\n";
            let written = iris_pty_write(master, msg.as_ptr(), msg.len());
            assert!(written > 0, "should write bytes");

            libc::usleep(100_000);

            let mut buf = [0u8; 4096];
            let nread = iris_pty_read(master, buf.as_mut_ptr(), buf.len());
            assert!(nread > 0, "should read bytes back");

            libc::kill(pid, libc::SIGTERM);
            iris_pty_close(master);
            libc::waitpid(pid, ptr::null_mut(), 0);
        }
    }

    #[test]
    fn test_pty_resize() {
        unsafe {
            let rc = iris_forkpty(80, 24);
            assert_eq!(rc, 0);
            let master = iris_forkpty_master();
            let pid = iris_forkpty_pid();

            let rc = iris_pty_resize(master, 120, 40);
            assert_eq!(rc, 0, "resize should succeed");

            libc::kill(pid, libc::SIGTERM);
            iris_pty_close(master);
            libc::waitpid(pid, ptr::null_mut(), 0);
        }
    }
}
