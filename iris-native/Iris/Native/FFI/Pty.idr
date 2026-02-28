module Iris.Native.FFI.Pty

import Data.Buffer

%foreign "C:iris_forkpty,libiris_native_support"
prim__forkpty : Bits16 -> Bits16 -> PrimIO Int

%foreign "C:iris_forkpty_master,libiris_native_support"
prim__forkptyMaster : PrimIO Int

%foreign "C:iris_forkpty_pid,libiris_native_support"
prim__forkptyPid : PrimIO Int

%foreign "C:iris_pty_read,libiris_native_support"
prim__ptyRead : Int -> Buffer -> Int -> PrimIO Int

%foreign "C:iris_pty_write,libiris_native_support"
prim__ptyWrite : Int -> Buffer -> Int -> PrimIO Int

%foreign "C:iris_pty_resize,libiris_native_support"
prim__ptyResize : Int -> Bits16 -> Bits16 -> PrimIO Int

%foreign "C:iris_pty_close,libiris_native_support"
prim__ptyClose : Int -> PrimIO Int

public export
record ForkResult where
  constructor MkForkResult
  masterFd : Int
  childPid : Int

||| Fork a PTY with the given columns and rows. Execs $SHELL in the child.
export
forkPty : (cols : Bits16) -> (rows : Bits16) -> IO (Either String ForkResult)
forkPty cols rows = do
  rc <- primIO (prim__forkpty cols rows)
  if rc < 0
    then pure (Left "forkpty failed")
    else do
      m <- primIO prim__forkptyMaster
      p <- primIO prim__forkptyPid
      pure (Right (MkForkResult m p))

||| Read bytes from a PTY master fd into a buffer. Returns bytes read.
export
ptyRead : (fd : Int) -> Buffer -> (maxLen : Int) -> IO Int
ptyRead fd buf len = primIO (prim__ptyRead fd buf len)

||| Write bytes to a PTY master fd from a buffer. Returns bytes written.
export
ptyWrite : (fd : Int) -> Buffer -> (len : Int) -> IO Int
ptyWrite fd buf len = primIO (prim__ptyWrite fd buf len)

||| Resize a PTY. Returns 0 on success.
export
ptyResize : (fd : Int) -> (cols : Bits16) -> (rows : Bits16) -> IO Int
ptyResize fd cols rows = primIO (prim__ptyResize fd cols rows)

||| Close a PTY master fd.
export
ptyClose : (fd : Int) -> IO Int
ptyClose fd = primIO (prim__ptyClose fd)
