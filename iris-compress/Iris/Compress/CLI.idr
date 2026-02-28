module Iris.Compress.CLI

import Data.String
import Iris.Compress.Config
import Iris.Compress.Discovery
import Iris.Compress.Execute
import Iris.Compress.Plan
import Iris.Compress.TimeUnit
import Iris.Compress.UUID
import Iris.Core.Parse
import System
import System.File

usage : String
usage =
  "Usage: iris-compress [OPTIONS]\n" ++
  "\n" ++
  "Options:\n" ++
  "  -d, --dir DIR         Directory to scan (default: ~/.ttyrec)\n" ++
  "  -o, --older-than N    Age threshold (default: 5m)\n" ++
  "                        Units: s=seconds, m=minutes, h=hours, d=days, w=weeks\n" ++
  "  -j, --jobs N          Parallel compression workers (default: CPU count)\n" ++
  "  -n, --dry-run         Show what would be done without doing it\n" ++
  "  -h, --help            Show this help message\n"

||| Parse CLI arguments into a Config, modifying the given default.
parseArgs : List String -> Config -> Either String Config
parseArgs [] cfg = Right cfg
parseArgs ("-h" :: _) _ = Left usage
parseArgs ("--help" :: _) _ = Left usage
parseArgs ("-n" :: rest) cfg = parseArgs rest ({ dryRun := True } cfg)
parseArgs ("--dry-run" :: rest) cfg = parseArgs rest ({ dryRun := True } cfg)
parseArgs ("-d" :: val :: rest) cfg = parseArgs rest ({ dir := val } cfg)
parseArgs ("--dir" :: val :: rest) cfg = parseArgs rest ({ dir := val } cfg)
parseArgs ("-o" :: val :: rest) cfg =
  case parseDuration val of
    Just d  => parseArgs rest ({ olderThan := d } cfg)
    Nothing => Left ("invalid duration: " ++ val)
parseArgs ("--older-than" :: val :: rest) cfg =
  case parseDuration val of
    Just d  => parseArgs rest ({ olderThan := d } cfg)
    Nothing => Left ("invalid duration: " ++ val)
parseArgs ("-j" :: val :: rest) cfg =
  case parseNat val of
    Just n  => parseArgs rest ({ jobs := n } cfg)
    Nothing => Left ("invalid job count: " ++ val)
parseArgs ("--jobs" :: val :: rest) cfg =
  case parseNat val of
    Just n  => parseArgs rest ({ jobs := n } cfg)
    Nothing => Left ("invalid job count: " ++ val)
parseArgs (arg :: _) _ = Left ("Unknown option: " ++ arg)

||| Print a message to stderr.
errLn : String -> IO ()
errLn msg = do
  _ <- fPutStrLn stderr msg
  pure ()

||| Remove a file, ignoring errors.
removeFileQuiet : String -> IO ()
removeFileQuiet path = do
  _ <- removeFile path
  pure ()

||| Execute a dry-run: print what would happen.
dryRunPlan : CompressionPlan -> IO ()
dryRunPlan plan = do
  let visible = filter (\a => describeAction a /= "") (actions plan)
  traverse_ (\a => putStrLn (describeAction a)) visible

||| Print skip messages for open files.
reportSkips : List Action -> IO ()
reportSkips [] = pure ()
reportSkips (Skip u FileOpen :: rest) = do
  errLn ("Skipping (open): " ++ uuid u)
  reportSkips rest
reportSkips (_ :: rest) = reportSkips rest

||| Execute the compression plan.
executePlan : Config -> CompressionPlan -> IO Nat
executePlan cfg plan = do
  let compressActions = filter isCompress (actions plan)
  let cleanActions = filter isClean (actions plan)
  reportSkips (actions plan)
  -- Clean partial .lz files first
  traverse_ doClean cleanActions
  -- Submit compression jobs
  case compressActions of
    [] => do putStrLn "No files to compress."; pure 0
    _ => do
      poolResult <- createPool (jobs cfg)
      case poolResult of
        Left err => do errLn err; pure 1
        Right pool => do
          traverse_ (submit pool) compressActions
          count <- finishPool pool
          failures <- collectResults pool count 0 0
          destroyPool pool
          putStrLn "Finished."
          pure failures
  where
    isCompress : Action -> Bool
    isCompress (CompressRaw _) = True
    isCompress (RecompressZst _) = True
    isCompress _ = False

    isClean : Action -> Bool
    isClean (CleanPartial _) = True
    isClean _ = False

    doClean : Action -> IO ()
    doClean (CleanPartial u) = do
      putStrLn ("Removing partial: " ++ uuid u ++ ".lz")
      removeFileQuiet (dir cfg ++ "/" ++ uuid u ++ ".lz")
    doClean _ = pure ()

    submit : Pool -> Action -> IO ()
    submit pool (CompressRaw u) = do
      _ <- submitRaw pool (dir cfg ++ "/" ++ uuid u)
      pure ()
    submit pool (RecompressZst u) = do
      _ <- submitZst pool (dir cfg ++ "/" ++ uuid u ++ ".ttyrec.zst")
      pure ()
    submit _ _ = pure ()

    collectResults : Pool -> Nat -> Nat -> Nat -> IO Nat
    collectResults _ Z _ fails = pure fails
    collectResults pool (S k) idx fails = do
      outcome <- getOutcome pool idx
      case outcome of
        Success path => do
          putStrLn ("Done: " ++ path)
          collectResults pool k (S idx) fails
        Failure path msg => do
          errLn ("FAILED: " ++ path ++ " (" ++ msg ++ ")")
          collectResults pool k (S idx) (S fails)

||| Get the user's home directory.
getHome : IO String
getHome = do
  Just home <- getEnv "HOME"
    | Nothing => pure "/tmp"
  pure home

||| Get the CPU count (best effort).
getCpuCount : IO Nat
getCpuCount = do
  rc <- System.system "sysctl -n hw.ncpu > /dev/null 2>&1"
  pure (if rc == 0 then 4 else 4)  -- TODO: read actual value via FFI

||| Normalize argument list (skip argv[0] if it's the binary name).
normalizeArgs : List String -> List String
normalizeArgs [] = []
normalizeArgs all@(arg0 :: rest) =
  if isPrefixOf "-" arg0
    then all
    else rest

public export
main : IO ()
main = do
  rawArgs <- getArgs
  let args = normalizeArgs rawArgs
  home <- getHome
  cpus <- getCpuCount
  let def = defaultConfig home cpus
  case parseArgs args def of
    Left msg => do
      errLn msg
      exitWith (ExitFailure 1)
    Right cfg => do
      result <- discoverFiles cfg
      case result of
        Left err => do
          errLn ("Error: " ++ err)
          exitWith (ExitFailure 1)
        Right plan => do
          let summary = planSummary plan (jobs cfg)
          let rawCount = length (filter isRaw (actions plan))
          let zstCount = length (filter isZst (actions plan))
          if rawCount + zstCount == 0
            then putStrLn "No files to compress."
            else do
              putStrLn summary
              if dryRun cfg
                then dryRunPlan plan
                else do
                  fails <- executePlan cfg plan
                  if fails > 0
                    then exitWith (ExitFailure 1)
                    else pure ()
  where
    isRaw : Action -> Bool
    isRaw (CompressRaw _) = True
    isRaw _ = False

    isZst : Action -> Bool
    isZst (RecompressZst _) = True
    isZst _ = False
