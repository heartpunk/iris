module Iris.Rec.CLI

import Data.Buffer
import Iris.Core.Frame
import Iris.Rec.Ttyrec.Write
import System
import System.Clock
import System.File
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

chunkSize : Int
chunkSize = 4096

captureTimestamp : IO (Nat, Nat)
captureTimestamp = do
  now <- clockTime UTC
  let secVal : Nat = cast (seconds now)
  let usecVal : Nat = cast ((nanoseconds now) `div` 1000)
  pure (secVal, usecVal)

readFramesLoop : Buffer -> List Frame -> IO (Either String (List Frame))
readFramesLoop buffer acc = do
  readResult <- readBufferData stdin buffer 0 chunkSize
  case readResult of
    Left err => pure (Left ("failed to read stdin: " ++ show err))
    Right bytesRead =>
      if bytesRead <= 0
        then pure (Right (reverse acc))
        else do
          payloadBytes <- readBufferBytes buffer bytesRead 0 []
          (secVal, usecVal) <- captureTimestamp
          let frame = MkFrame secVal usecVal payloadBytes
          readFramesLoop buffer (frame :: acc)

readFramesFromStdin : IO (Either String (List Frame))
readFramesFromStdin = do
  maybeBuffer <- newBuffer chunkSize
  case maybeBuffer of
    Nothing => pure (Left "failed to allocate stdin read buffer")
    Just buffer => readFramesLoop buffer []

recordOnce : String -> IO ()
recordOnce path = do
  stdinRead <- readFramesFromStdin
  case stdinRead of
    Left err => do
      putStrLn err
      exitWith (ExitFailure 1)
    Right frames => do
      wrote <- writeTtyrec path frames
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
