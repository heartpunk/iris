module Compress.Main

import Iris.Compress.TimeUnit
import System

-- Takes an equality proof; always True at runtime.
-- Compilation verifies the proof holds (type checker rejects Refl if not).
isProven : a = b -> Bool
isProven _ = True

runPure : String -> Bool -> IO Nat
runPure name passed = do
  putStrLn ((if passed then "PASS " else "FAIL ") ++ name)
  pure (if passed then 0 else 1)

propertyMany : (Nat -> Bool) -> Nat -> Bool
propertyMany prop Z = prop 0
propertyMany prop (S k) = prop (S k) && propertyMany prop k

-- Helper: check Maybe Duration equality by fields.
durationEq : Maybe Duration -> Maybe Duration -> Bool
durationEq Nothing Nothing = True
durationEq (Just a) (Just b) = value a == value b && unit a == unit b
durationEq _ _ = False

-- ==========================================================================
-- TimeUnit computed proofs (compile-time verified)
-- ==========================================================================

proofToSecondsIdentity : toSeconds (MkDuration 42 Seconds) = 42
proofToSecondsIdentity = Refl

proofToSecondsMinutes : toSeconds (MkDuration 1 Minutes) = 60
proofToSecondsMinutes = Refl

proofToSecondsHours : toSeconds (MkDuration 1 Hours) = 3600
proofToSecondsHours = Refl

proofToSecondsDays : toSeconds (MkDuration 1 Days) = 86400
proofToSecondsDays = Refl

proofToSecondsWeeks : toSeconds (MkDuration 1 Weeks) = 604800
proofToSecondsWeeks = Refl

proofToSecondsZero : toSeconds (MkDuration 0 Minutes) = 0
proofToSecondsZero = Refl

proofParseTimeUnitS : parseTimeUnit 's' = Just Seconds
proofParseTimeUnitS = Refl

proofParseTimeUnitM : parseTimeUnit 'm' = Just Minutes
proofParseTimeUnitM = Refl

proofParseTimeUnitH : parseTimeUnit 'h' = Just Hours
proofParseTimeUnitH = Refl

proofParseTimeUnitD : parseTimeUnit 'd' = Just Days
proofParseTimeUnitD = Refl

proofParseTimeUnitW : parseTimeUnit 'w' = Just Weeks
proofParseTimeUnitW = Refl

proofParseTimeUnitBad : parseTimeUnit 'x' = Nothing
proofParseTimeUnitBad = Refl

-- ==========================================================================
-- parseDuration runtime unit tests
-- (span from Data.List doesn't reduce at compile time)
-- ==========================================================================

unitParseDuration5m : Bool
unitParseDuration5m = durationEq (parseDuration "5m") (Just (MkDuration 5 Minutes))

unitParseDuration30s : Bool
unitParseDuration30s = durationEq (parseDuration "30s") (Just (MkDuration 30 Seconds))

unitParseDuration2h : Bool
unitParseDuration2h = durationEq (parseDuration "2h") (Just (MkDuration 2 Hours))

unitParseDuration1d : Bool
unitParseDuration1d = durationEq (parseDuration "1d") (Just (MkDuration 1 Days))

unitParseDuration1w : Bool
unitParseDuration1w = durationEq (parseDuration "1w") (Just (MkDuration 1 Weeks))

unitParseDurationBare : Bool
unitParseDurationBare = durationEq (parseDuration "10") (Just (MkDuration 10 Minutes))

unitParseDurationEmpty : Bool
unitParseDurationEmpty = durationEq (parseDuration "") Nothing

unitParseDurationNoDigits : Bool
unitParseDurationNoDigits = durationEq (parseDuration "m") Nothing

unitParseDurationBadSuffix : Bool
unitParseDurationBadSuffix = durationEq (parseDuration "5x") Nothing

public export
main : IO ()
main = do
  timeUnitProofs <- runPure "proof/time-unit-conversions"
    (isProven proofToSecondsIdentity
      && isProven proofToSecondsMinutes
      && isProven proofToSecondsHours
      && isProven proofToSecondsDays
      && isProven proofToSecondsWeeks
      && isProven proofToSecondsZero)
  parseTimeUnitProofs <- runPure "proof/parse-time-unit"
    (isProven proofParseTimeUnitS
      && isProven proofParseTimeUnitM
      && isProven proofParseTimeUnitH
      && isProven proofParseTimeUnitD
      && isProven proofParseTimeUnitW
      && isProven proofParseTimeUnitBad)
  parseDurationUnits <- runPure "unit/parse-duration-cases"
    (unitParseDuration5m
      && unitParseDuration30s
      && unitParseDuration2h
      && unitParseDuration1d
      && unitParseDuration1w
      && unitParseDurationBare
      && unitParseDurationEmpty
      && unitParseDurationNoDigits
      && unitParseDurationBadSuffix)

  let failures = timeUnitProofs + parseTimeUnitProofs + parseDurationUnits
  putStrLn ("failures: " ++ show failures)
  if failures == 0
    then pure ()
    else exitWith (ExitFailure 1)
