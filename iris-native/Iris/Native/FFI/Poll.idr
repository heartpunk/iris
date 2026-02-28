module Iris.Native.FFI.Poll

%foreign "C:iris_poll_clear,libiris_native_support"
prim__pollClear : PrimIO ()

%foreign "C:iris_poll_add,libiris_native_support"
prim__pollAdd : Int -> PrimIO Int

%foreign "C:iris_poll_wait,libiris_native_support"
prim__pollWait : Int -> PrimIO Int

%foreign "C:iris_poll_readable,libiris_native_support"
prim__pollReadable : Int -> PrimIO Int

%foreign "C:iris_poll_error,libiris_native_support"
prim__pollError : Int -> PrimIO Int

||| Clear the poll fd set.
export
pollClear : IO ()
pollClear = primIO prim__pollClear

||| Add an fd to the poll set. Returns the index, or -1 if full.
export
pollAdd : (fd : Int) -> IO Int
pollAdd fd = primIO (prim__pollAdd fd)

||| Wait for events. timeout == -1 blocks indefinitely.
||| Returns number of ready fds, 0 on timeout, -1 on error.
export
pollWait : (timeoutMs : Int) -> IO Int
pollWait ms = primIO (prim__pollWait ms)

||| Check if fd at index is readable after pollWait. Returns 1 if readable.
export
pollReadable : (idx : Int) -> IO Bool
pollReadable idx = do
  r <- primIO (prim__pollReadable idx)
  pure (r == 1)

||| Check if fd at index has error/hangup after pollWait. Returns 1 if error.
export
pollError : (idx : Int) -> IO Bool
pollError idx = do
  r <- primIO (prim__pollError idx)
  pure (r == 1)
