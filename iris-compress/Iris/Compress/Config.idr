module Iris.Compress.Config

import Iris.Compress.TimeUnit

||| Configuration for a compression run, parsed from CLI arguments.
public export
record Config where
  constructor MkConfig
  dir       : String    -- directory to scan (default ~/.ttyrec)
  olderThan : Duration  -- age threshold for eligibility (default 5m)
  jobs      : Nat       -- parallel compression workers (default CPU count)
  dryRun    : Bool      -- report without acting

public export
Show Config where
  show c = "Config { dir = " ++ show (dir c)
        ++ ", olderThan = " ++ show (olderThan c)
        ++ ", jobs = " ++ show (jobs c)
        ++ ", dryRun = " ++ show (dryRun c)
        ++ " }"

||| Default configuration. The caller must fill in `jobs` (CPU count)
||| and `dir` (home directory) at runtime.
public export
defaultConfig : (home : String) -> (cpus : Nat) -> Config
defaultConfig home cpus = MkConfig
  { dir       = home ++ "/.ttyrec"
  , olderThan = MkDuration 5 Minutes
  , jobs      = cpus
  , dryRun    = False
  }
