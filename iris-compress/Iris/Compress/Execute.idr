module Iris.Compress.Execute

import Iris.Compress.UUID

-- ==========================================================================
-- FFI bindings to the Rust support crate (iris-compress-support)
-- ==========================================================================

-- File system operations

%foreign "C:iris_file_mtime,libiris_compress_support"
prim__fileMtime : String -> PrimIO Int

%foreign "C:iris_is_file_open,libiris_compress_support"
prim__isFileOpen : String -> PrimIO Int

-- Thread pool operations

%foreign "C:iris_pool_create,libiris_compress_support"
prim__poolCreate : Int -> PrimIO Int

%foreign "C:iris_pool_submit_raw,libiris_compress_support"
prim__poolSubmitRaw : Int -> String -> PrimIO Int

%foreign "C:iris_pool_submit_zst,libiris_compress_support"
prim__poolSubmitZst : Int -> String -> PrimIO Int

%foreign "C:iris_pool_finish,libiris_compress_support"
prim__poolFinish : Int -> PrimIO Int

%foreign "C:iris_pool_status,libiris_compress_support"
prim__poolStatus : Int -> Int -> PrimIO Int

%foreign "C:iris_pool_message,libiris_compress_support"
prim__poolMessage : Int -> Int -> PrimIO String

%foreign "C:iris_pool_destroy,libiris_compress_support"
prim__poolDestroy : Int -> PrimIO ()

-- ==========================================================================
-- High-level wrappers
-- ==========================================================================

||| Get a file's modification time as seconds since epoch.
||| Returns negative on error.
public export
fileMtime : String -> IO Int
fileMtime path = primIO (prim__fileMtime path)

||| Check if a file is currently open by another process.
public export
isFileOpen : String -> IO Bool
isFileOpen path = do
  result <- primIO (prim__isFileOpen path)
  pure (result > 0)

||| Opaque handle to a compression thread pool.
public export
record Pool where
  constructor MkPool
  handle : Int

||| Create a thread pool with the given number of workers.
public export
createPool : Nat -> IO (Either String Pool)
createPool jobs = do
  h <- primIO (prim__poolCreate (cast jobs))
  if h < 0
    then pure (Left "failed to create thread pool")
    else pure (Right (MkPool h))

||| Submit a raw file for compression (lzip -9).
public export
submitRaw : Pool -> String -> IO Bool
submitRaw pool path = do
  rc <- primIO (prim__poolSubmitRaw (handle pool) path)
  pure (rc == 0)

||| Submit a zst file for recompression (zstd -dc | lzip -9).
public export
submitZst : Pool -> String -> IO Bool
submitZst pool path = do
  rc <- primIO (prim__poolSubmitZst (handle pool) path)
  pure (rc == 0)

||| Wait for all submitted jobs to complete. Returns the number of results.
public export
finishPool : Pool -> IO Nat
finishPool pool = do
  n <- primIO (prim__poolFinish (handle pool))
  pure (cast n)

||| Outcome of a single compression job.
public export
data Outcome = Success String | Failure String String

public export
Show Outcome where
  show (Success path) = "Done: " ++ path
  show (Failure path msg) = "FAILED: " ++ path ++ " (" ++ msg ++ ")"

||| Get the outcome of the i-th completed job.
public export
getOutcome : Pool -> Nat -> IO Outcome
getOutcome pool idx = do
  status <- primIO (prim__poolStatus (handle pool) (cast idx))
  msg <- primIO (prim__poolMessage (handle pool) (cast idx))
  if status == 0
    then pure (Success msg)
    else pure (Failure msg (if status == 1 then "compression failed" else "verification failed"))

||| Destroy the pool and free resources.
public export
destroyPool : Pool -> IO ()
destroyPool pool = primIO (prim__poolDestroy (handle pool))

||| Summarize outcomes: count successes and failures.
public export
summarizeOutcomes : List Outcome -> (Nat, Nat)
summarizeOutcomes [] = (0, 0)
summarizeOutcomes (Success _ :: rest) =
  let (s, f) = summarizeOutcomes rest in (S s, f)
summarizeOutcomes (Failure _ _ :: rest) =
  let (s, f) = summarizeOutcomes rest in (s, S f)
