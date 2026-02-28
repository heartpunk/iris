module Iris.Replay.Ttyrec.Parse

import Data.Buffer
import Data.List
import Iris.Core.Frame
import public Iris.Replay.Decompress
import System.File
import System.File.Buffer

public export
record ParseError where
  constructor MkParseError
  offset  : Nat
  message : String

byteToNat : Bits8 -> Nat
byteToNat b = cast (the Integer (cast b))

u32LE : Bits8 -> Bits8 -> Bits8 -> Bits8 -> Nat
u32LE b0 b1 b2 b3 =
  byteToNat b0
    + (byteToNat b1 * 256)
    + (byteToNat b2 * 65536)
    + (byteToNat b3 * 16777216)

parseBytesAt : Nat -> List Bits8 -> List Frame -> Either ParseError (List Frame)
parseBytesAt _ [] acc = Right (reverse acc)
parseBytesAt offset bytes acc =
  case bytes of
    b0 :: b1 :: b2 :: b3 :: b4 :: b5 :: b6 :: b7 :: b8 :: b9 :: b10 :: b11 :: rest =>
      let secVal = u32LE b0 b1 b2 b3
          usecVal = u32LE b4 b5 b6 b7
          lenVal = u32LE b8 b9 b10 b11
          (payloadBytes, trailing) = splitAt lenVal rest
       in if length payloadBytes < lenVal
            then Left (MkParseError offset "truncated ttyrec payload")
            else
              parseBytesAt
                (offset + 12 + lenVal)
                trailing
                (MkFrame secVal usecVal payloadBytes :: acc)
    _ => Left (MkParseError offset "truncated ttyrec header")

public export
parseBytes : List Bits8 -> Either ParseError (List Frame)
parseBytes bytes = parseBytesAt 0 bytes []

readU32At : Buffer -> Int -> IO Nat
readU32At buffer offset = do
  b0 <- getBits8 buffer offset
  b1 <- getBits8 buffer (offset + 1)
  b2 <- getBits8 buffer (offset + 2)
  b3 <- getBits8 buffer (offset + 3)
  pure (u32LE b0 b1 b2 b3)

readPayload : Buffer -> Int -> Int -> IO (List Bits8)
readPayload buffer start len = go 0 []
  where
    go : Int -> List Bits8 -> IO (List Bits8)
    go index acc =
      if index >= len
        then pure (reverse acc)
        else do
          b <- getBits8 buffer (start + index)
          go (index + 1) (b :: acc)

parseBufferAt : Buffer -> Int -> Int -> List Frame -> IO (Either ParseError (List Frame))
parseBufferAt buffer size offset acc =
  if offset == size
    then pure (Right (reverse acc))
    else
      let remaining = size - offset in
      if remaining < 12
        then pure (Left (MkParseError (cast offset) "truncated ttyrec header"))
        else do
          secVal <- readU32At buffer offset
          usecVal <- readU32At buffer (offset + 4)
          lenVal <- readU32At buffer (offset + 8)
          let lenInt = cast lenVal
          let frameSize = 12 + lenInt
          if remaining < frameSize
            then pure (Left (MkParseError (cast offset) "truncated ttyrec payload"))
            else do
              payloadBytes <- readPayload buffer (offset + 12) lenInt
              parseBufferAt
                buffer
                size
                (offset + frameSize)
                (MkFrame secVal usecVal payloadBytes :: acc)

public export
parseFile : String -> Maybe Compression -> IO (Either ParseError (List Frame))
parseFile path override = do
  decompResult <- decompressFile path override
  case decompResult of
    Left err => pure (Left (MkParseError 0 err))
    Right result => do
      loaded <- createBufferFromFile (decompressedPath result)
      case loaded of
        Left err => do
          cleanupDecompressed result
          pure (Left (MkParseError 0 ("failed to read ttyrec file: " ++ show err)))
        Right buffer => do
          size <- rawSize buffer
          parsed <- parseBufferAt buffer size 0 []
          cleanupDecompressed result
          pure parsed
