module Iris.Compress.Plan

import Iris.Compress.UUID

||| Reason a file was skipped during planning.
public export
data SkipReason
  = FileOpen           -- lsof reports the file is in use
  | TooRecent          -- file mtime is within the age threshold
  | AlreadyLz          -- file is already lzip-compressed
  | NotRecognized      -- filename doesn't match any known pattern

public export
Eq SkipReason where
  FileOpen == FileOpen = True
  TooRecent == TooRecent = True
  AlreadyLz == AlreadyLz = True
  NotRecognized == NotRecognized = True
  _ == _ = False

public export
Show SkipReason where
  show FileOpen = "open"
  show TooRecent = "too recent"
  show AlreadyLz = "already compressed"
  show NotRecognized = "not recognized"

||| An action to take on a single file.
public export
data Action
  = CompressRaw ValidUUID       -- lzip -9 <uuid>
  | RecompressZst ValidUUID     -- zstd -dc <uuid>.ttyrec.zst | lzip -9
  | CleanPartial ValidUUID      -- remove stale <uuid>.lz before compressing raw
  | Skip ValidUUID SkipReason   -- skip with reason (for reporting)
  | Ignore String               -- silently ignore unrecognized file

public export
Show Action where
  show (CompressRaw u) = "compress (raw -> lz): " ++ show u
  show (RecompressZst u) = "recompress (zst -> lz): " ++ show u
  show (CleanPartial u) = "remove partial: " ++ show u ++ ".lz"
  show (Skip u reason) = "skip (" ++ show reason ++ "): " ++ show u
  show (Ignore s) = "ignore: " ++ s

||| A compression plan: the list of actions to execute.
public export
record CompressionPlan where
  constructor MkPlan
  actions : List Action

public export
Show CompressionPlan where
  show p = "CompressionPlan [" ++ show (length (actions p)) ++ " actions]"

||| Describe an action for dry-run output.
public export
describeAction : Action -> String
describeAction (CompressRaw u) = "Would compress (raw -> lz): " ++ show u
describeAction (RecompressZst u) = "Would recompress (zst -> lz): " ++ show u
describeAction (CleanPartial u) = "Would remove partial: " ++ show u ++ ".lz"
describeAction (Skip u reason) = "Skipping (" ++ show reason ++ "): " ++ show u
describeAction (Ignore _) = ""

||| Count actions by type.
countRaw : List Action -> Nat
countRaw [] = 0
countRaw (CompressRaw _ :: rest) = S (countRaw rest)
countRaw (_ :: rest) = countRaw rest

countZst : List Action -> Nat
countZst [] = 0
countZst (RecompressZst _ :: rest) = S (countZst rest)
countZst (_ :: rest) = countZst rest

||| Generate a summary line for the plan.
||| "Found N uncompressed + M zst files (T total), using J parallel jobs..."
public export
planSummary : CompressionPlan -> Nat -> String
planSummary plan jobs =
  let raw = countRaw (actions plan)
      zst = countZst (actions plan)
   in "Found " ++ show raw ++ " uncompressed + " ++ show zst
      ++ " zst files (" ++ show (raw + zst) ++ " total), using "
      ++ show jobs ++ " parallel jobs..."
