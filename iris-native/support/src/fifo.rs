use libc::{c_char, c_int};

/// Create a FIFO (named pipe) at the given path.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn iris_mkfifo(path: *const c_char) -> c_int {
    if path.is_null() {
        return -1;
    }
    libc::mkfifo(path, 0o600)
}

/// Open a file in read-only, non-blocking mode.
/// Returns the fd on success, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn iris_open_rdonly_nonblock(path: *const c_char) -> c_int {
    if path.is_null() {
        return -1;
    }
    libc::open(path, libc::O_RDONLY | libc::O_NONBLOCK)
}

/// Unlink (delete) a file at the given path.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn iris_unlink(path: *const c_char) -> c_int {
    if path.is_null() {
        return -1;
    }
    libc::unlink(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn test_mkfifo_and_unlink() {
        unsafe {
            let tmpdir = std::env::var("TMPDIR").unwrap_or_else(|_| "/tmp".to_string());
            let path_str = format!("{}/iris-test-fifo-{}", tmpdir, std::process::id());
            let path = CString::new(path_str).unwrap();

            // Clean up any leftover from previous test
            iris_unlink(path.as_ptr());

            let rc = iris_mkfifo(path.as_ptr());
            assert_eq!(rc, 0, "mkfifo should succeed");

            // Open non-blocking should succeed
            let fd = iris_open_rdonly_nonblock(path.as_ptr());
            assert!(fd >= 0, "open should succeed");
            libc::close(fd);

            // Unlink should succeed
            let rc = iris_unlink(path.as_ptr());
            assert_eq!(rc, 0, "unlink should succeed");
        }
    }

    #[test]
    fn test_mkfifo_null_path() {
        unsafe {
            assert_eq!(iris_mkfifo(std::ptr::null()), -1);
            assert_eq!(iris_open_rdonly_nonblock(std::ptr::null()), -1);
            assert_eq!(iris_unlink(std::ptr::null()), -1);
        }
    }
}
