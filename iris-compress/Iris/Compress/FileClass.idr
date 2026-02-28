module Iris.Compress.FileClass

import Data.String
import Iris.Compress.UUID

||| Classification of files found in the ttyrec directory.
public export
data FileClass
  = RawTtyrec ValidUUID         -- bare UUID filename, uncompressed
  | ZstTtyrec ValidUUID         -- UUID.ttyrec.zst, zstd-compressed
  | AlreadyCompressed ValidUUID -- UUID.lz, already lzip'd
  | Unrecognized String         -- anything else

public export
Eq FileClass where
  RawTtyrec a == RawTtyrec b = a == b
  ZstTtyrec a == ZstTtyrec b = a == b
  AlreadyCompressed a == AlreadyCompressed b = a == b
  Unrecognized a == Unrecognized b = a == b
  _ == _ = False

public export
Show FileClass where
  show (RawTtyrec u) = "RawTtyrec " ++ show u
  show (ZstTtyrec u) = "ZstTtyrec " ++ show u
  show (AlreadyCompressed u) = "AlreadyCompressed " ++ show u
  show (Unrecognized s) = "Unrecognized " ++ show s

||| Strip a known suffix from a string, returning the prefix if it matches.
stripSuffix : String -> String -> Maybe String
stripSuffix suffix s =
  let sLen = length s
      suffLen = length suffix
   in if suffLen > sLen
        then Nothing
        else if substr (sLen `minus` suffLen) suffLen s == suffix
               then Just (substr 0 (sLen `minus` suffLen) s)
               else Nothing

||| Classify a filename (basename only, not full path).
public export
classifyFile : String -> FileClass
classifyFile name =
  case stripSuffix ".lz" name of
    Just base => case validateUUID base of
      Just u  => AlreadyCompressed u
      Nothing => Unrecognized name
    Nothing => case stripSuffix ".ttyrec.zst" name of
      Just base => case validateUUID base of
        Just u  => ZstTtyrec u
        Nothing => Unrecognized name
      Nothing => case validateUUID name of
        Just u  => RawTtyrec u
        Nothing => Unrecognized name
