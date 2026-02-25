module Iris.Rec.Ttyrec.Write

import Data.Buffer
import Iris.Core.Frame
import System.File

toByte : Integer -> Bits8
toByte value = cast value

u32Max : Integer
u32Max = 4294967295

public export
encodeU32LE : Nat -> Either String (List Bits8)
encodeU32LE value =
  let n : Integer = cast value in
  if n > u32Max
    then Left ("u32 value out of range: " ++ show value)
    else Right
      [ toByte (n `mod` 256)
      , toByte ((n `div` 256) `mod` 256)
      , toByte ((n `div` 65536) `mod` 256)
      , toByte ((n `div` 16777216) `mod` 256)
      ]

public export
encodeFrame : Frame -> Either String (List Bits8)
encodeFrame frame = do
  secBytes <- encodeU32LE (sec frame)
  usecBytes <- encodeU32LE (usec frame)
  lenBytes <- encodeU32LE (length (payload frame))
  pure (secBytes ++ usecBytes ++ lenBytes ++ payload frame)

public export
encodeFrames : List Frame -> Either String (List Bits8)
encodeFrames [] = Right []
encodeFrames (frame :: rest) = do
  encodedFrame <- encodeFrame frame
  encodedRest <- encodeFrames rest
  pure (encodedFrame ++ encodedRest)

fillBuffer : Buffer -> Int -> List Bits8 -> IO ()
fillBuffer _ _ [] = pure ()
fillBuffer buffer index (byte :: rest) = do
  setBits8 buffer index byte
  fillBuffer buffer (index + 1) rest

toBuffer : List Bits8 -> IO (Either String Buffer)
toBuffer bytes = do
  maybeBuffer <- newBuffer (cast (length bytes))
  case maybeBuffer of
    Nothing => pure (Left "failed to allocate buffer")
    Just buffer => do
      fillBuffer buffer 0 bytes
      pure (Right buffer)

public export
writeTtyrec : String -> List Frame -> IO (Either String ())
writeTtyrec path frames = do
  case encodeFrames frames of
    Left err => pure (Left err)
    Right bytes => do
      let byteCount = cast (length bytes)
      buffered <- toBuffer bytes
      case buffered of
        Left err => pure (Left err)
        Right buffer => do
          wrote <- writeBufferToFile path buffer byteCount
          case wrote of
            Left ferr => pure (Left ("failed to write ttyrec file: " ++ show ferr))
            Right () => pure (Right ())
