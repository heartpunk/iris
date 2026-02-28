module Iris.Compress.TimeUnit

import Data.List
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

||| Parse a single-character time unit suffix.
public export
parseTimeUnit : Char -> Maybe TimeUnit
parseTimeUnit 's' = Just Seconds
parseTimeUnit 'm' = Just Minutes
parseTimeUnit 'h' = Just Hours
parseTimeUnit 'd' = Just Days
parseTimeUnit 'w' = Just Weeks
parseTimeUnit _   = Nothing

||| Parse a duration string like "5m", "30s", "2h", "1d", "1w".
||| A bare number with no suffix is treated as minutes.
public export
parseDuration : String -> Maybe Duration
parseDuration s =
  case unpack s of
    [] => Nothing
    chars =>
      let (numChars, rest) = span isDigit chars
       in case (numChars, rest) of
            ([], _) => Nothing
            (ds, []) => case parseNat (pack ds) of
                          Just n  => Just (MkDuration n Minutes)
                          Nothing => Nothing
            (ds, [u]) => case (parseNat (pack ds), parseTimeUnit u) of
                           (Just n, Just tu) => Just (MkDuration n tu)
                           _ => Nothing
            _ => Nothing
