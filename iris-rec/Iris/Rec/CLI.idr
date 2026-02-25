module Iris.Rec.CLI

import Iris.Core.Frame
import Iris.Rec.Ttyrec.Write
import System
import System.File

usage : String
usage =
  "iris-rec commands:\n" ++
  "  record <output-path>  Capture stdin and write ttyrec output"

normalizeArgs : List String -> List String
normalizeArgs [] = []
normalizeArgs all@(arg0 :: rest) =
  if arg0 == "record"
    then all
    else rest

readAllStdin : IO (Either String String)
readAllStdin = do
  input <- fRead stdin
  case input of
    Left err => pure (Left ("failed to read stdin: " ++ show err))
    Right content => pure (Right content)

recordOnce : String -> IO ()
recordOnce path = do
  stdinRead <- readAllStdin
  case stdinRead of
    Left err => do
      putStrLn err
      exitWith (ExitFailure 1)
    Right content => do
      let frame = MkFrame 0 0 (stringToBytes content)
      wrote <- writeTtyrec path [frame]
      case wrote of
        Left err => do
          putStrLn err
          exitWith (ExitFailure 1)
        Right () => pure ()

public export
main : IO ()
main = do
  rawArgs <- getArgs
  let args = normalizeArgs rawArgs
  case args of
    ["record", outputPath] => recordOnce outputPath
    _ => putStrLn usage
