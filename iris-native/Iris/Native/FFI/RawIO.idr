module Iris.Native.FFI.RawIO

import Data.Buffer
import Iris.Native.FFI.Pty

%foreign "C:iris_stdin_read,libiris_native_support"
prim__stdinRead : Buffer -> Int -> PrimIO Int

%foreign "C:iris_stdout_write,libiris_native_support"
prim__stdoutWrite : Buffer -> Int -> PrimIO Int

%foreign "C:iris_waitpid_nohang,libiris_native_support"
prim__waitpidNohang : Int -> PrimIO Int

||| Read raw bytes from stdin into a buffer. Returns bytes read, 0 on EOF, -1 on error.
||| No String conversion — preserves all bytes including NUL and high bytes.
export
stdinRead : Buffer -> (maxLen : Int) -> IO Int
stdinRead buf len = primIO (prim__stdinRead buf len)

||| Write raw bytes from a buffer to stdout. Returns bytes written, -1 on error.
||| No String conversion — preserves all bytes including escape sequences and high bytes.
export
stdoutWrite : Buffer -> (len : Int) -> IO Int
stdoutWrite buf len = primIO (prim__stdoutWrite buf len)

||| Non-blocking waitpid. Returns:
|||   > 0: child exited (returns pid)
|||   0: child still running
|||   -1: error (no such child)
export
waitpidNohang : (pid : Int) -> IO Int
waitpidNohang pid = primIO (prim__waitpidNohang pid)

||| Write a buffer's contents to stdout. Convenience wrapper.
export
bufToStdout : Buffer -> (len : Int) -> IO Int
bufToStdout = stdoutWrite

||| Read from stdin and write to an fd (e.g. PTY master).
||| Returns bytes forwarded, 0 on EOF, -1 on error.
export
stdinToFd : Buffer -> (maxLen : Int) -> (fd : Int) -> IO Int
stdinToFd buf maxLen fd = do
  n <- stdinRead buf maxLen
  if n <= 0
    then pure n
    else ptyWrite fd buf n

||| Read from an fd (e.g. PTY master) and write to stdout.
||| Returns bytes forwarded, 0 on EOF, -1 on error.
export
fdToStdout : Buffer -> (maxLen : Int) -> (fd : Int) -> IO Int
fdToStdout buf maxLen fd = do
  n <- ptyRead fd buf maxLen
  if n <= 0
    then pure n
    else stdoutWrite buf n
