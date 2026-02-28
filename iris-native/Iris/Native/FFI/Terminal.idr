module Iris.Native.FFI.Terminal

%foreign "C:iris_terminal_enter_raw,libiris_native_support"
prim__enterRaw : PrimIO Int

%foreign "C:iris_terminal_restore,libiris_native_support"
prim__restore : PrimIO Int

%foreign "C:iris_terminal_get_cols,libiris_native_support"
prim__getCols : PrimIO Bits16

%foreign "C:iris_terminal_get_rows,libiris_native_support"
prim__getRows : PrimIO Bits16

||| Enter raw terminal mode on stdin. Returns 0 on success.
export
enterRawMode : IO Int
enterRawMode = primIO prim__enterRaw

||| Restore original terminal mode. Returns 0 on success.
export
restoreTerminal : IO Int
restoreTerminal = primIO prim__restore

||| Get terminal width in columns. Returns 0 on error.
export
getTermCols : IO Bits16
getTermCols = primIO prim__getCols

||| Get terminal height in rows. Returns 0 on error.
export
getTermRows : IO Bits16
getTermRows = primIO prim__getRows
