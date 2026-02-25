module Iris.Rec.CLI

import Data.Buffer
import Iris.Core.Frame
import Iris.Rec.Ttyrec.Write
import System
import System.File.Buffer

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

readBufferBytes : Buffer -> Int -> Int -> List Bits8 -> IO (List Bits8)
readBufferBytes buffer size index acc =
  if index >= size
    then pure (reverse acc)
    else do
      b <- getBits8 buffer index
      readBufferBytes buffer size (index + 1) (b :: acc)

readAllStdinBytes : IO (Either String (List Bits8))
readAllStdinBytes = do
  loaded <- createBufferFromFile "/dev/stdin"
  case loaded of
    Left err => pure (Left ("failed to read stdin: " ++ show err))
    Right buffer => do
      size <- rawSize buffer
      bytes <- readBufferBytes buffer size 0 []
      pure (Right bytes)

recordOnce : String -> IO ()
recordOnce path = do
  stdinRead <- readAllStdinBytes
  case stdinRead of
    Left err => do
      putStrLn err
      exitWith (ExitFailure 1)
    Right payloadBytes => do
      let frame = MkFrame 0 0 payloadBytes
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
