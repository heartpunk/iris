use libc::{self, c_int, pollfd};
use std::ptr::addr_of_mut;

const MAX_POLL_FDS: usize = 64;

static mut POLL_FDS: [pollfd; MAX_POLL_FDS] = [pollfd {
    fd: -1,
    events: 0,
    revents: 0,
}; MAX_POLL_FDS];
static mut POLL_COUNT: usize = 0;

/// Clear the poll set.
#[no_mangle]
pub unsafe extern "C" fn iris_poll_clear() {
    POLL_COUNT = 0;
    let fds = &mut *addr_of_mut!(POLL_FDS);
    for pfd in fds.iter_mut() {
        pfd.fd = -1;
        pfd.events = 0;
        pfd.revents = 0;
    }
}

/// Add an fd to the poll set. Returns the index, or -1 if full.
#[no_mangle]
pub unsafe extern "C" fn iris_poll_add(fd: c_int) -> c_int {
    if POLL_COUNT >= MAX_POLL_FDS {
        return -1;
    }
    let idx = POLL_COUNT;
    let fds = &mut *addr_of_mut!(POLL_FDS);
    fds[idx].fd = fd;
    fds[idx].events = libc::POLLIN;
    fds[idx].revents = 0;
    POLL_COUNT += 1;
    idx as c_int
}

/// Wait for events. timeout_ms == -1 means block indefinitely.
/// Returns number of fds with events, 0 on timeout, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn iris_poll_wait(timeout_ms: c_int) -> c_int {
    if POLL_COUNT == 0 {
        return 0;
    }
    let fds = &mut *addr_of_mut!(POLL_FDS);
    libc::poll(fds.as_mut_ptr(), POLL_COUNT as libc::nfds_t, timeout_ms)
}

/// Check if fd at index is readable after poll_wait. Returns 1 if readable, 0 if not.
#[no_mangle]
pub unsafe extern "C" fn iris_poll_readable(idx: c_int) -> c_int {
    let i = idx as usize;
    if i >= POLL_COUNT {
        return 0;
    }
    let fds = &*addr_of_mut!(POLL_FDS);
    if fds[i].revents & libc::POLLIN != 0 {
        1
    } else {
        0
    }
}

/// Check if fd at index has error/hangup after poll_wait. Returns 1 if error, 0 if not.
#[no_mangle]
pub unsafe extern "C" fn iris_poll_error(idx: c_int) -> c_int {
    let i = idx as usize;
    if i >= POLL_COUNT {
        return 0;
    }
    let fds = &*addr_of_mut!(POLL_FDS);
    if fds[i].revents & (libc::POLLERR | libc::POLLHUP) != 0 {
        1
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_poll_add_and_clear() {
        unsafe {
            iris_poll_clear();

            let idx = iris_poll_add(0); // stdin
            assert_eq!(idx, 0);

            let idx2 = iris_poll_add(1); // stdout
            assert_eq!(idx2, 1);

            iris_poll_clear();
            // After clear, adding should start at 0 again
            let idx3 = iris_poll_add(0);
            assert_eq!(idx3, 0);
        }
    }

    #[test]
    fn test_poll_readable_out_of_bounds() {
        unsafe {
            iris_poll_clear();
            assert_eq!(iris_poll_readable(0), 0);
            assert_eq!(iris_poll_readable(99), 0);
        }
    }

    #[test]
    fn test_poll_error_out_of_bounds() {
        unsafe {
            iris_poll_clear();
            assert_eq!(iris_poll_error(0), 0);
            assert_eq!(iris_poll_error(99), 0);
        }
    }

    #[test]
    fn test_poll_wait_empty_set() {
        unsafe {
            iris_poll_clear();
            let rc = iris_poll_wait(0);
            assert_eq!(rc, 0, "empty poll set should return 0");
        }
    }
}
