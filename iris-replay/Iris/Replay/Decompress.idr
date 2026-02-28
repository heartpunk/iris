module Iris.Replay.Decompress

import Data.Buffer
import Data.String
import Iris.Core.Parse
import System
import System.File
import System.File.Buffer

public export
data Compression = Lzip | Gzip | Zstd | Xz | Bzip2 | Uncompressed

public export
Eq Compression where
  Lzip == Lzip = True
  Gzip == Gzip = True
  Zstd == Zstd = True
  Xz == Xz = True
  Bzip2 == Bzip2 = True
  Uncompressed == Uncompressed = True
  _ == _ = False

public export
record DecompressResult where
  constructor MkDecompressResult
  decompressedPath : String
  needsCleanup : Bool

public export
compressionName : Compression -> String
compressionName Lzip = "lzip"
compressionName Gzip = "gzip"
compressionName Zstd = "zstd"
compressionName Xz = "xz"
compressionName Bzip2 = "bzip2"
compressionName Uncompressed = "none"

public export
parseCompression : String -> Maybe Compression
parseCompression "lzip" = Just Lzip
parseCompression "gzip" = Just Gzip
parseCompression "zstd" = Just Zstd
parseCompression "xz" = Just Xz
parseCompression "bzip2" = Just Bzip2
parseCompression "none" = Just Uncompressed
parseCompression _ = Nothing

public export
detectByExtension : String -> Compression
detectByExtension path =
  if isSuffixOf ".lz" path then Lzip
  else if isSuffixOf ".gz" path then Gzip
  else if isSuffixOf ".zst" path then Zstd
  else if isSuffixOf ".xz" path then Xz
  else if isSuffixOf ".bz2" path then Bzip2
  else Uncompressed

public export
detectByMagic : List Bits8 -> Compression
detectByMagic (0x4C :: 0x5A :: 0x49 :: 0x50 :: _) = Lzip
detectByMagic (0x1F :: 0x8B :: _) = Gzip
detectByMagic (0x28 :: 0xB5 :: 0x2F :: 0xFD :: _) = Zstd
detectByMagic (0xFD :: 0x37 :: 0x7A :: 0x58 :: 0x5A :: 0x00 :: _) = Xz
detectByMagic (0x42 :: 0x5A :: 0x68 :: _) = Bzip2
detectByMagic _ = Uncompressed

public export
validateCompression : (ext : Compression) -> (magic : Compression) -> Either String Compression
validateCompression ext magic =
  if ext == magic
    then Right ext
    else Left ("cowardly refuse to proceed: extension suggests "
      ++ compressionName ext
      ++ " but magic bytes disagree; use --force-decompression=<alg> to override")

public export
decompressCmd : Compression -> String
decompressCmd Lzip = "lzip -d -c"
decompressCmd Gzip = "gzip -d -c"
decompressCmd Zstd = "zstd -d -c"
decompressCmd Xz = "xz -d -c"
decompressCmd Bzip2 = "bzip2 -d -c"
decompressCmd Uncompressed = ""

readMagicList : Buffer -> Int -> Int -> IO (List Bits8)
readMagicList buffer idx count =
  if idx >= count
    then pure []
    else do
      b <- getBits8 buffer idx
      rest <- readMagicList buffer (idx + 1) count
      pure (b :: rest)

readMagicBytes : String -> IO (Either String (List Bits8))
readMagicBytes path = do
  result <- openFile path Read
  case result of
    Left err => pure (Left ("failed to open file: " ++ show err))
    Right file => do
      maybeBuffer <- newBuffer 6
      case maybeBuffer of
        Nothing => do
          closeFile file
          pure (Left "failed to allocate buffer for magic bytes")
        Just buffer => do
          readResult <- readBufferData file buffer 0 6
          closeFile file
          case readResult of
            Left err => pure (Left ("failed to read magic bytes: " ++ show err))
            Right bytesRead => do
              bytes <- readMagicList buffer 0 bytesRead
              pure (Right bytes)

makeTempFile : IO (Either String String)
makeTempFile = do
  result <- popen "mktemp /tmp/iris-decompress.XXXXXX" Read
  case result of
    Left err => pure (Left ("failed to create temp file: " ++ show err))
    Right process => do
      output <- fRead process
      exitCode <- pclose process
      case output of
        Left err => pure (Left ("failed to read mktemp output: " ++ show err))
        Right path =>
          if exitCode == 0
            then pure (Right (trim path))
            else pure (Left "mktemp failed")

doDecompress : Compression -> String -> IO (Either String DecompressResult)
doDecompress alg inputPath = do
  tmpResult <- makeTempFile
  case tmpResult of
    Left err => pure (Left err)
    Right tmpPath => do
      let cmd = decompressCmd alg ++ " " ++ quoteArg inputPath ++ " > " ++ quoteArg tmpPath
      exitCode <- system cmd
      if exitCode == 0
        then pure (Right (MkDecompressResult tmpPath True))
        else do
          _ <- removeFile tmpPath
          pure (Left ("decompression failed with " ++ compressionName alg
            ++ " (exit " ++ show exitCode ++ ")"))

public export
decompressFile : String -> Maybe Compression -> IO (Either String DecompressResult)
decompressFile path Nothing = do
  let ext = detectByExtension path
  magicResult <- readMagicBytes path
  case magicResult of
    Left err => pure (Left err)
    Right bytes =>
      let magic = detectByMagic bytes
       in case validateCompression ext magic of
            Left err => pure (Left err)
            Right Uncompressed => pure (Right (MkDecompressResult path False))
            Right alg => doDecompress alg path
decompressFile path (Just Uncompressed) = pure (Right (MkDecompressResult path False))
decompressFile path (Just alg) = doDecompress alg path

public export
cleanupDecompressed : DecompressResult -> IO ()
cleanupDecompressed result =
  if needsCleanup result
    then do _ <- removeFile (decompressedPath result); pure ()
    else pure ()
