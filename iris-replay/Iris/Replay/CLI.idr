module Iris.Replay.CLI

import Data.Buffer
import Iris.Core.Frame
import Iris.Replay.Replay
import Iris.Replay.Search
import Iris.Replay.Ttyrec.Parse
import System
import System.File.Buffer

usage : String
usage =
  "iris-replay commands:\n" ++
  "  replay <path>          Replay a ttyrec to stdout\n" ++
  "  search <path> <query>  Search frame payload content\n" ++
  "  info <path>            Print basic frame stats"

normalizeArgs : List String -> List String
normalizeArgs [] = []
normalizeArgs all@(arg0 :: rest) =
  if arg0 == "replay" || arg0 == "search" || arg0 == "info"
    then all
    else rest

formatParseError : ParseError -> String
formatParseError err =
  "parse error at byte " ++ show (offset err) ++ ": " ++ message err

byteToChar : Bits8 -> Char
byteToChar b = chr (cast (the Integer (cast b)))

payloadText : Frame -> String
payloadText frame = pack (map byteToChar (payload frame))

sanitizeChar : Char -> Char
sanitizeChar '\n' = ' '
sanitizeChar '\r' = ' '
sanitizeChar '\t' = ' '
sanitizeChar ch = ch

takeChars : Nat -> List Char -> List Char
takeChars Z _ = []
takeChars (S k) [] = []
takeChars (S k) (ch :: rest) = ch :: takeChars k rest

snippetLimit : Nat
snippetLimit = 80

frameSnippet : Frame -> String
frameSnippet frame =
  let chars = map sanitizeChar (unpack (payloadText frame))
   in pack (takeChars snippetLimit chars)

formatMatch : FrameMatch -> String
formatMatch match =
  let matchedFrame = frame match
   in "frame=" ++ show (frameIndex match)
        ++ " ts=" ++ show (sec matchedFrame) ++ "." ++ show (usec matchedFrame)
        ++ " snippet=" ++ frameSnippet matchedFrame

printMatches : List FrameMatch -> IO ()
printMatches [] = pure ()
printMatches (match :: rest) = do
  putStrLn (formatMatch match)
  printMatches rest

frameTimestampMicros : Frame -> Integer
frameTimestampMicros frame =
  (cast (sec frame) * 1000000) + cast (usec frame)

timestampBounds : List Frame -> Maybe (Integer, Integer)
timestampBounds [] = Nothing
timestampBounds (frame :: rest) = go start start rest
  where
    start : Integer
    start = frameTimestampMicros frame

    go : Integer -> Integer -> List Frame -> Maybe (Integer, Integer)
    go low high [] = Just (low, high)
    go low high (next :: tail) =
      let ts = frameTimestampMicros next
          nextLow = if ts < low then ts else low
          nextHigh = if ts > high then ts else high
       in go nextLow nextHigh tail

formatTimestampMicros : Integer -> String
formatTimestampMicros micros =
  let secVal = micros `div` 1000000
      usecVal = micros `mod` 1000000
   in show secVal ++ "." ++ show usecVal

exitWithMessage : String -> IO ()
exitWithMessage msg = do
  putStrLn msg
  exitWith (ExitFailure 1)

runReplay : String -> IO ()
runReplay path = do
  result <- replayFile path
  case result of
    Left err => exitWithMessage (formatParseError err)
    Right () => pure ()

runSearch : String -> String -> IO ()
runSearch path query = do
  parsed <- parseFile path
  case parsed of
    Left err => exitWithMessage (formatParseError err)
    Right frames => do
      let matches = searchFrames query frames
      putStrLn ("matches: " ++ show (length matches))
      printMatches matches

runInfo : String -> IO ()
runInfo path = do
  parsed <- parseFile path
  case parsed of
    Left err => exitWithMessage (formatParseError err)
    Right frames => do
      loaded <- createBufferFromFile path
      case loaded of
        Left err => exitWithMessage ("failed to read ttyrec file: " ++ show err)
        Right buffer => do
          size <- rawSize buffer
          putStrLn ("frames: " ++ show (length frames))
          putStrLn ("file-size: " ++ show size)
          case timestampBounds frames of
            Nothing => do
              putStrLn "timestamp-range: n/a"
              putStrLn "duration-us: 0"
            Just (startMicros, endMicros) => do
              putStrLn ("timestamp-range: " ++ formatTimestampMicros startMicros ++ ".." ++ formatTimestampMicros endMicros)
              putStrLn ("duration-us: " ++ show (endMicros - startMicros))

public export
main : IO ()
main = do
  rawArgs <- getArgs
  let args = normalizeArgs rawArgs
  case args of
    ["replay", path] => runReplay path
    ["search", path, query] => runSearch path query
    ["info", path] => runInfo path
    _ => exitWithMessage usage
