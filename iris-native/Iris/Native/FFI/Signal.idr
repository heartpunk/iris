module Iris.Native.FFI.Signal

%foreign "C:iris_signal_setup,libiris_native_support"
prim__signalSetup : PrimIO Int

%foreign "C:iris_signal_check_winch,libiris_native_support"
prim__signalCheckWinch : PrimIO Int

%foreign "C:iris_signal_check_child,libiris_native_support"
prim__signalCheckChild : PrimIO Int

%foreign "C:iris_signal_check_term,libiris_native_support"
prim__signalCheckTerm : PrimIO Int

||| Install signal handlers for SIGWINCH, SIGCHLD, SIGTERM, SIGINT.
||| Returns 0 on success, -1 on error.
export
signalSetup : IO Int
signalSetup = primIO prim__signalSetup

||| Check and clear the SIGWINCH flag. Returns True if fired since last check.
export
signalCheckWinch : IO Bool
signalCheckWinch = do
  r <- primIO prim__signalCheckWinch
  pure (r == 1)

||| Check and clear the SIGCHLD flag. Returns True if fired since last check.
export
signalCheckChild : IO Bool
signalCheckChild = do
  r <- primIO prim__signalCheckChild
  pure (r == 1)

||| Check and clear the SIGTERM/SIGINT flag. Returns True if fired since last check.
export
signalCheckTerm : IO Bool
signalCheckTerm = do
  r <- primIO prim__signalCheckTerm
  pure (r == 1)
