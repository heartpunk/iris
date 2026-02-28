module Iris.Replay.CLI

import Data.Buffer
import Data.String
import Iris.Core.Frame
import Iris.Replay.Decompress
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
  "  dump <path>            Dump each frame with index, timestamp, length, and content\n" ++
  "  raw-dump <path>        Dump raw payload bytes to stdout (no metadata or sanitization)\n" ++
  "\n" ++
  "options:\n" ++
  "  --force-decompression=<alg>  Override auto-detection (lzip|gzip|zstd|xz|bzip2|none)"

normalizeArgs : List String -> List String
normalizeArgs [] = []
normalizeArgs all@(arg0 :: rest) =
  if arg0 == "replay" || arg0 == "search" || arg0 == "info" || arg0 == "dump" || arg0 == "raw-dump"
       || arg0 == "--help" || arg0 == "-h" || isPrefixOf "--force-decompression=" arg0
    then all
    else rest

data ForceDecompResult = NotForceDecomp | InvalidAlg String | ValidAlg Compression

forceDecompPrefix : String
forceDecompPrefix = "-" ++ "-force-decompression="

forceDecompPrefixLen : Nat
forceDecompPrefixLen = 22

parseForceDecomp : String -> ForceDecompResult
parseForceDecomp arg =
  if isPrefixOf forceDecompPrefix arg
    then let value = substr forceDecompPrefixLen (minus (length arg) forceDecompPrefixLen) arg
          in case parseCompression value of
               Just alg => ValidAlg alg
               Nothing => InvalidAlg value
    else NotForceDecomp

extractForceDecompression : List String -> Either String (Maybe Compression, List String)
extractForceDecompression args = go [] args
  where
    go : List String -> List String -> Either String (Maybe Compression, List String)
    go acc [] = Right (Nothing, reverse acc)
    go acc (arg :: rest) =
      case parseForceDecomp arg of
        ValidAlg alg => Right (Just alg, reverse acc ++ rest)
        InvalidAlg value => Left ("unknown decompression algorithm: " ++ value
          ++ "; expected one of: lzip, gzip, zstd, xz, bzip2, none")
        NotForceDecomp => go (arg :: acc) rest

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

padLeftWith : Nat -> Char -> String -> String
padLeftWith width pad text =
  let chars = unpack text
      missing = minus width (length chars)
   in pack (repeatChar missing pad ++ chars)

public export
formatTimestampMicros : Integer -> String
formatTimestampMicros micros =
  let secVal = micros `div` 1000000
      usecVal = micros `mod` 1000000
   in show secVal ++ "." ++ padLeftWith 6 '0' (show usecVal)

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

runReplay : String -> Maybe Compression -> IO ()
runReplay path override = do
  result <- replayFile path override
  case result of
    Left err => exitWithMessage err
    Right () => pure ()

runSearch : String -> String -> Maybe Compression -> IO ()
runSearch path query override = do
  parsed <- parseFile path override
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

runDump : String -> Maybe Compression -> IO ()
runDump path override = do
  parsed <- parseFile path override
  case parsed of
    Left err => exitWithMessage (formatParseError err)
    Right frames => printDumpLines 0 frames

runRawDump : String -> Maybe Compression -> IO ()
runRawDump path override = do
  result <- replayFile path override
  case result of
    Left err => exitWithMessage err
    Right () => pure ()

runInfo : String -> Maybe Compression -> IO ()
runInfo path override = do
  decompResult <- decompressFile path override
  case decompResult of
    Left err => exitWithMessage err
    Right result => do
      parsed <- parseFile (decompressedPath result) (Just Uncompressed)
      case parsed of
        Left err => do
          cleanupDecompressed result
          exitWithMessage (formatParseError err)
        Right frames => do
          loaded <- createBufferFromFile (decompressedPath result)
          case loaded of
            Left err => do
              cleanupDecompressed result
              exitWithMessage ("failed to read ttyrec file: " ++ show err)
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
              cleanupDecompressed result

public export
main : IO ()
main = do
  rawArgs <- getArgs
  let args = normalizeArgs rawArgs
  case extractForceDecompression args of
    Left err => exitWithMessage err
    Right (override, cmdArgs) =>
      case cmdArgs of
        ["--help"] => do
          putStrLn usage
          exitWith ExitSuccess
        ["-h"] => do
          putStrLn usage
          exitWith ExitSuccess
        ["replay", path] => runReplay path override
        ["search", path, query] => runSearch path query override
        ["info", path] => runInfo path override
        ["dump", path] => runDump path override
        ["raw-dump", path] => runRawDump path override
        _ => exitWithMessage usage
