use libc::{c_int, sigaction, sighandler_t, SA_RESTART, SIGCHLD, SIGINT, SIGTERM, SIGWINCH};
use std::sync::atomic::{AtomicBool, Ordering};

static WINCH_FLAG: AtomicBool = AtomicBool::new(false);
static CHILD_FLAG: AtomicBool = AtomicBool::new(false);
static TERM_FLAG: AtomicBool = AtomicBool::new(false);

extern "C" fn handle_winch(_: c_int) {
    WINCH_FLAG.store(true, Ordering::Relaxed);
}

extern "C" fn handle_child(_: c_int) {
    CHILD_FLAG.store(true, Ordering::Relaxed);
}

extern "C" fn handle_term(_: c_int) {
    TERM_FLAG.store(true, Ordering::Relaxed);
}

/// Install signal handlers for SIGWINCH, SIGCHLD, SIGTERM, and SIGINT.
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn iris_signal_setup() -> c_int {
    let signals: [(c_int, extern "C" fn(c_int)); 4] = [
        (SIGWINCH, handle_winch),
        (SIGCHLD, handle_child),
        (SIGTERM, handle_term),
        (SIGINT, handle_term), // SIGINT uses same handler as SIGTERM
    ];

    for (sig, handler) in &signals {
        let mut sa: sigaction = std::mem::zeroed();
        sa.sa_sigaction = *handler as sighandler_t;
        sa.sa_flags = SA_RESTART;
        if sigaction(*sig, &sa, std::ptr::null_mut()) != 0 {
            return -1;
        }
    }
    0
}

/// Check and clear the SIGWINCH flag. Returns 1 if fired since last check.
#[no_mangle]
pub extern "C" fn iris_signal_check_winch() -> c_int {
    if WINCH_FLAG.swap(false, Ordering::Relaxed) {
        1
    } else {
        0
    }
}

/// Check and clear the SIGCHLD flag. Returns 1 if fired since last check.
#[no_mangle]
pub extern "C" fn iris_signal_check_child() -> c_int {
    if CHILD_FLAG.swap(false, Ordering::Relaxed) {
        1
    } else {
        0
    }
}

/// Check and clear the SIGTERM/SIGINT flag. Returns 1 if fired since last check.
#[no_mangle]
pub extern "C" fn iris_signal_check_term() -> c_int {
    if TERM_FLAG.swap(false, Ordering::Relaxed) {
        1
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_signal_setup_succeeds() {
        unsafe {
            let rc = iris_signal_setup();
            assert_eq!(rc, 0, "signal setup should succeed");
        }
    }

    #[test]
    fn test_flags_initially_clear() {
        // Flags should be clear (or we clear them by checking)
        let _ = iris_signal_check_winch();
        let _ = iris_signal_check_child();
        let _ = iris_signal_check_term();

        assert_eq!(iris_signal_check_winch(), 0, "WINCH should be clear");
        assert_eq!(iris_signal_check_child(), 0, "CHILD should be clear");
        assert_eq!(iris_signal_check_term(), 0, "TERM should be clear");
    }

    #[test]
    fn test_raise_and_check_winch() {
        unsafe {
            iris_signal_setup();
            // Clear any pending
            let _ = iris_signal_check_winch();

            libc::raise(SIGWINCH);
            assert_eq!(iris_signal_check_winch(), 1, "WINCH should fire");
            assert_eq!(iris_signal_check_winch(), 0, "WINCH should auto-clear");
        }
    }

    #[test]
    fn test_raise_and_check_child() {
        unsafe {
            iris_signal_setup();
            let _ = iris_signal_check_child();

            libc::raise(SIGCHLD);
            assert_eq!(iris_signal_check_child(), 1, "CHILD should fire");
            assert_eq!(iris_signal_check_child(), 0, "CHILD should auto-clear");
        }
    }
}
