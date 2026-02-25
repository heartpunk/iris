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

writePayload : List Bits8 -> IO ()
writePayload [] = pure ()
writePayload bytes = do
  maybeBuffer <- newBuffer (cast (length bytes))
  case maybeBuffer of
    Nothing => pure ()
    Just buffer => do
      fillBuffer buffer 0 bytes
      _ <- writeBufferToFile "/dev/stdout" buffer (cast (length bytes))
      pure ()

public export
replayUntimed : List Frame -> IO ()
replayUntimed [] = pure ()
replayUntimed (frame :: rest) = do
  writePayload (payload frame)
  replayUntimed rest

public export
replayFile : String -> IO (Either ParseError ())
replayFile path = do
  parsed <- parseFile path
  case parsed of
    Left err => pure (Left err)
    Right frames => do
      replayUntimed frames
      pure (Right ())
