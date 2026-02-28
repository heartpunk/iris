module Iris.Native.FFI.Fifo

%foreign "C:iris_mkfifo,libiris_native_support"
prim__mkfifo : String -> PrimIO Int

%foreign "C:iris_open_rdonly_nonblock,libiris_native_support"
prim__openRdOnlyNonblock : String -> PrimIO Int

%foreign "C:iris_unlink,libiris_native_support"
prim__unlink : String -> PrimIO Int

||| Create a FIFO (named pipe) at the given path with mode 0600.
||| Returns 0 on success, -1 on error.
export
mkFifo : (path : String) -> IO Int
mkFifo path = primIO (prim__mkfifo path)

||| Open a file read-only and non-blocking.
||| Returns the fd on success, -1 on error.
export
openRdOnlyNonblock : (path : String) -> IO Int
openRdOnlyNonblock path = primIO (prim__openRdOnlyNonblock path)

||| Unlink (delete) a file.
||| Returns 0 on success, -1 on error.
export
unlinkFile : (path : String) -> IO Int
unlinkFile path = primIO (prim__unlink path)
