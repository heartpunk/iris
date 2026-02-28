module Iris.Compress.Discovery

import Data.List
import Data.String
import System
import System.Directory
import System.File
import Iris.Compress.Config
import Iris.Compress.Execute
import Iris.Compress.FileClass
import Iris.Compress.Plan
import Iris.Compress.TimeUnit
import Iris.Compress.UUID

||| List non-hidden entries in a directory (no recursion).
public export
scanDir : String -> IO (Either String (List String))
scanDir path = do
  result <- listDir path
  case result of
    Left err => pure (Left ("failed to open directory: " ++ show err))
    Right entries => pure (Right (filter (not . isPrefixOf ".") entries))

||| Check if a file exists at the given path.
fileExists : String -> IO Bool
fileExists path = do
  result <- openFile path Read
  case result of
    Left _ => pure False
    Right f => do closeFile f; pure True

||| Get the age of a file in seconds (current time - mtime).
||| Returns 0 on error (treating the file as too recent to compress).
public export
fileAgeSecs : String -> IO Nat
fileAgeSecs path = do
  now <- time
  mtime <- fileMtime path
  pure (if mtime < 0 then 0 else cast (now - cast mtime))

||| Determine action for a raw ttyrec after age/open checks pass.
rawEligibleAction : String -> ValidUUID -> IO Action
rawEligibleAction dir u = do
  lzExists <- fileExists (dir ++ "/" ++ uuid u ++ ".lz")
  pure (if lzExists then CleanPartial u else CompressRaw u)

||| Check open status and partial .lz for a raw ttyrec known to be old enough.
rawOldEnough : String -> ValidUUID -> IO Action
rawOldEnough dir u = do
  inUse <- isFileOpen (dir ++ "/" ++ uuid u)
  if inUse
    then pure (Skip u FileOpen)
    else rawEligibleAction dir u

||| Check eligibility (age + open) and return action for a raw ttyrec.
rawAction : Config -> String -> ValidUUID -> IO Action
rawAction cfg dir u = do
  age <- fileAgeSecs (dir ++ "/" ++ uuid u)
  if age < toSeconds (olderThan cfg)
    then pure (Skip u TooRecent)
    else rawOldEnough dir u

||| Check open status for a zst ttyrec known to be old enough.
zstOldEnough : String -> ValidUUID -> IO Action
zstOldEnough dir u = do
  inUse <- isFileOpen (dir ++ "/" ++ uuid u ++ ".ttyrec.zst")
  pure (if inUse then Skip u FileOpen else RecompressZst u)

||| Check eligibility and return action for a zst ttyrec.
zstAction : Config -> String -> ValidUUID -> IO Action
zstAction cfg dir u = do
  age <- fileAgeSecs (dir ++ "/" ++ uuid u ++ ".ttyrec.zst")
  if age < toSeconds (olderThan cfg)
    then pure (Skip u TooRecent)
    else zstOldEnough dir u

||| Classify a file and determine the appropriate action.
classifyAction : Config -> String -> String -> IO Action
classifyAction cfg dir name =
  case classifyFile name of
    RawTtyrec u => rawAction cfg dir u
    ZstTtyrec u => zstAction cfg dir u
    AlreadyCompressed u => pure (Skip u AlreadyLz)
    Unrecognized _ => pure (Ignore name)

||| Build actions from a list of filenames.
buildActions : Config -> String -> List String -> IO (List Action)
buildActions _ _ [] = pure []
buildActions cfg dir (name :: rest) = do
  action <- classifyAction cfg dir name
  others <- buildActions cfg dir rest
  pure (action :: others)

||| Discover files and build a compression plan.
public export
discoverFiles : Config -> IO (Either String CompressionPlan)
discoverFiles cfg = do
  result <- scanDir (dir cfg)
  case result of
    Left err => pure (Left err)
    Right entries => do
      actions <- buildActions cfg (dir cfg) entries
      pure (Right (MkPlan actions))
