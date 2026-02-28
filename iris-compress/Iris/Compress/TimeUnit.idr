module Iris.Compress.TimeUnit

import Iris.Core.Parse

||| Time unit suffixes for the --older-than flag.
public export
data TimeUnit = Seconds | Minutes | Hours | Days | Weeks

public export
Eq TimeUnit where
  Seconds == Seconds = True
  Minutes == Minutes = True
  Hours == Hours = True
  Days == Days = True
  Weeks == Weeks = True
  _ == _ = False

public export
Show TimeUnit where
  show Seconds = "s"
  show Minutes = "m"
  show Hours   = "h"
  show Days    = "d"
  show Weeks   = "w"

||| A duration is a numeric value paired with a time unit.
public export
record Duration where
  constructor MkDuration
  value : Nat
  unit  : TimeUnit

public export
Show Duration where
  show d = show (value d) ++ show (unit d)

||| Convert a duration to seconds.
public export
toSeconds : Duration -> Nat
toSeconds (MkDuration n Seconds) = n
toSeconds (MkDuration n Minutes) = n * 60
toSeconds (MkDuration n Hours)   = n * 3600
toSeconds (MkDuration n Days)    = n * 86400
toSeconds (MkDuration n Weeks)   = n * 604800
