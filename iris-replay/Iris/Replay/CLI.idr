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
  "  info <path>            Print basic frame stats\n" ++
  "  dump <path>            Dump each frame with index, timestamp, length, and content"

normalizeArgs : List String -> List String
normalizeArgs [] = []
normalizeArgs all@(arg0 :: rest) =
  if arg0 == "replay" || arg0 == "search" || arg0 == "info" || arg0 == "dump"
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

repeatChar : Nat -> Char -> List Char
repeatChar Z _ = []
repeatChar (S k) ch = ch :: repeatChar k ch

padLeft : Nat -> Char -> String -> String
padLeft width pad text =
  let chars = unpack text
      missing = minus width (length chars)
   in pack (repeatChar missing pad ++ chars)

public export
formatTimestampMicros : Integer -> String
formatTimestampMicros micros =
  let secVal = micros `div` 1000000
      usecVal = micros `mod` 1000000
   in show secVal ++ "." ++ padLeft 6 '0' (show usecVal)

formatMatch : FrameMatch -> String
formatMatch match =
  let matchedFrame = frame match
   in "frame=" ++ show (frameIndex match)
        ++ " ts=" ++ formatTimestampMicros (frameTimestampMicros matchedFrame)
        ++ " snippet=" ++ frameSnippet matchedFrame

printMatches : List FrameMatch -> IO ()
printMatches [] = pure ()
printMatches (match :: rest) = do
  putStrLn (formatMatch match)
  printMatches rest

exitWithMessage : String -> IO ()
exitWithMessage msg = do
  putStrLn msg
  exitWith (ExitFailure 1)

runReplay : String -> IO ()
runReplay path = do
  result <- replayFile path
  case result of
    Left err => exitWithMessage err
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

sanitizePayload : Frame -> String
sanitizePayload frame =
  pack (map sanitizeChar (unpack (payloadText frame)))

formatDumpLine : Nat -> Frame -> String
formatDumpLine idx frame =
  "frame=" ++ show idx
    ++ " ts=" ++ formatTimestampMicros (frameTimestampMicros frame)
    ++ " len=" ++ show (length (payload frame))
    ++ " payload=" ++ sanitizePayload frame

printDumpLines : Nat -> List Frame -> IO ()
printDumpLines _ [] = pure ()
printDumpLines idx (frame :: rest) = do
  putStrLn (formatDumpLine idx frame)
  printDumpLines (S idx) rest

runDump : String -> IO ()
runDump path = do
  parsed <- parseFile path
  case parsed of
    Left err => exitWithMessage (formatParseError err)
    Right frames => printDumpLines 0 frames

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
    ["--help"] => do
      putStrLn usage
      exitWith ExitSuccess
    ["-h"] => do
      putStrLn usage
      exitWith ExitSuccess
    ["replay", path] => runReplay path
    ["search", path, query] => runSearch path query
    ["info", path] => runInfo path
    ["dump", path] => runDump path
    _ => exitWithMessage usage
