module Iris.Replay.Replay

import Data.Buffer
import Iris.Core.Frame
import Iris.Replay.Ttyrec.Parse
import System.File

fillBuffer : Buffer -> Int -> List Bits8 -> IO ()
fillBuffer _ _ [] = pure ()
fillBuffer buffer index (byte :: rest) = do
  setBits8 buffer index byte
  fillBuffer buffer (index + 1) rest

formatParseError : ParseError -> String
formatParseError err =
  "parse error at byte " ++ show (offset err) ++ ": " ++ message err

writePayload : List Bits8 -> IO (Either String ())
writePayload [] = pure (Right ())
writePayload bytes = do
  maybeBuffer <- newBuffer (cast (length bytes))
  case maybeBuffer of
    -- This allocation-failure branch is difficult to force deterministically in tests.
    Nothing => pure (Left "failed to allocate buffer")
    Just buffer => do
      fillBuffer buffer 0 bytes
      wrote <- writeBufferToFile "/dev/stdout" buffer (cast (length bytes))
      case wrote of
        Left err => pure (Left ("failed to write replay output: " ++ show err))
        Right () => pure (Right ())

public export
replayUntimed : List Frame -> IO (Either String ())
replayUntimed [] = pure (Right ())
replayUntimed (frame :: rest) = do
  wrote <- writePayload (payload frame)
  case wrote of
    Left err => pure (Left err)
    Right () => replayUntimed rest

public export
replayFile : String -> IO (Either String ())
replayFile path = do
  parsed <- parseFile path
  case parsed of
    Left err => pure (Left (formatParseError err))
    Right frames => replayUntimed frames
