module Iris.Replay.Replay

import Data.Buffer
import Iris.Core.Frame
import Iris.Replay.Decompress
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

prependBytes : List Bits8 -> List Bits8 -> List Bits8
prependBytes [] acc = acc
prependBytes (byte :: rest) acc = prependBytes rest (byte :: acc)

collectPayloadsReversed : List Frame -> List Bits8 -> List Bits8
collectPayloadsReversed [] acc = acc
collectPayloadsReversed (frame :: rest) acc =
  collectPayloadsReversed rest (prependBytes (payload frame) acc)

collectPayloads : List Frame -> List Bits8
collectPayloads frames = reverse (collectPayloadsReversed frames [])

public export
replayUntimed : List Frame -> IO (Either String ())
replayUntimed frames = writePayload (collectPayloads frames)

public export
replayFile : String -> Maybe Compression -> IO (Either String ())
replayFile path override = do
  parsed <- parseFile path override
  case parsed of
    Left err => pure (Left (formatParseError err))
    Right frames => replayUntimed frames
