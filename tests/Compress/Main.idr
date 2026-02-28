module Compress.Main

import Iris.Compress.TimeUnit
import Iris.Compress.UUID
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

-- LCG random number generator (same as iris-tests).
lcgModulus : Integer
lcgModulus = 4294967296

nextSeed : Integer -> Integer
nextSeed seed = (1664525 * seed + 1013904223) `mod` lcgModulus

randomNat : Integer -> (Nat, Integer)
randomNat seed =
  let s = nextSeed seed
   in (cast (s `mod` 10000), s)

-- Pick a TimeUnit from a seed (0-4 -> one of five units).
pickUnit : Integer -> (TimeUnit, Integer)
pickUnit seed =
  let s = nextSeed seed
      idx = s `mod` 5
   in (case idx of
         0 => Seconds
         1 => Minutes
         2 => Hours
         3 => Days
         _ => Weeks, s)

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

-- ==========================================================================
-- TimeUnit property tests
-- ==========================================================================

-- Property: parseDuration roundtrip — show then parse recovers the duration.
propertyParseDurationRoundtrip : Nat -> Bool
propertyParseDurationRoundtrip seedNat =
  let seed = cast seedNat
      (n, s1) = randomNat seed
      (tu, _) = pickUnit s1
      dur = MkDuration n tu
      rendered = show dur
   in durationEq (parseDuration rendered) (Just dur)

-- Property: larger units produce more seconds for the same value (n > 0).
propertyMonotonicity : Nat -> Bool
propertyMonotonicity seedNat =
  let (n, _) = randomNat (cast seedNat)
      n1 = S n  -- ensure n > 0
   in toSeconds (MkDuration n1 Seconds) <= toSeconds (MkDuration n1 Minutes)
      && toSeconds (MkDuration n1 Minutes) <= toSeconds (MkDuration n1 Hours)
      && toSeconds (MkDuration n1 Hours) <= toSeconds (MkDuration n1 Days)
      && toSeconds (MkDuration n1 Days) <= toSeconds (MkDuration n1 Weeks)

-- Property: toSeconds (MkDuration 0 unit) == 0 for any unit.
propertyZeroDuration : Nat -> Bool
propertyZeroDuration seedNat =
  let (tu, _) = pickUnit (cast seedNat)
   in toSeconds (MkDuration 0 tu) == 0

-- Property: bare number (no suffix) is treated as minutes.
propertyBareIsMinutes : Nat -> Bool
propertyBareIsMinutes seedNat =
  let (n, _) = randomNat (cast seedNat)
   in durationEq (parseDuration (show n)) (Just (MkDuration n Minutes))

-- ==========================================================================
-- UUID unit tests
-- (isUUIDFormat uses unpack which may not reduce at compile time)
-- ==========================================================================

unitUUIDValid : Bool
unitUUIDValid = isUUIDFormat "550e8400-e29b-41d4-a716-446655440000" == True

unitUUIDAllZeros : Bool
unitUUIDAllZeros = isUUIDFormat "00000000-0000-0000-0000-000000000000" == True

unitUUIDAllF : Bool
unitUUIDAllF = isUUIDFormat "ffffffff-ffff-ffff-ffff-ffffffffffff" == True

unitUUIDUppercase : Bool
unitUUIDUppercase = isUUIDFormat "550E8400-E29B-41D4-A716-446655440000" == False

unitUUIDTooShort : Bool
unitUUIDTooShort = isUUIDFormat "550e8400-e29b-41d4-a716" == False

unitUUIDNoHyphens : Bool
unitUUIDNoHyphens = isUUIDFormat "550e8400e29b41d4a716446655440000" == False

unitUUIDExtraChars : Bool
unitUUIDExtraChars = isUUIDFormat "550e8400-e29b-41d4-a716-446655440000x" == False

unitUUIDEmpty : Bool
unitUUIDEmpty = isUUIDFormat "" == False

unitUUIDValidateValid : Bool
unitUUIDValidateValid = case validateUUID "550e8400-e29b-41d4-a716-446655440000" of
  Just v  => uuid v == "550e8400-e29b-41d4-a716-446655440000"
  Nothing => False

unitUUIDValidateInvalid : Bool
unitUUIDValidateInvalid = case validateUUID "not-a-uuid" of
  Just _  => False
  Nothing => True

-- isHexChar compile-time proofs (simple character comparison reduces fine).
proofHexCharDigit : isHexChar '0' = True
proofHexCharDigit = Refl

proofHexCharA : isHexChar 'a' = True
proofHexCharA = Refl

proofHexCharF : isHexChar 'f' = True
proofHexCharF = Refl

proofHexCharUpperA : isHexChar 'A' = False
proofHexCharUpperA = Refl

proofHexCharG : isHexChar 'g' = False
proofHexCharG = Refl

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

  let rounds = 199
  roundtrip <- runPure "property/parse-duration-roundtrip-200-seeds"
    (propertyMany propertyParseDurationRoundtrip rounds)
  monotonicity <- runPure "property/time-unit-monotonicity-200-seeds"
    (propertyMany propertyMonotonicity rounds)
  zeroDur <- runPure "property/zero-duration-200-seeds"
    (propertyMany propertyZeroDuration rounds)
  bareMinutes <- runPure "property/bare-is-minutes-200-seeds"
    (propertyMany propertyBareIsMinutes rounds)

  uuidUnits <- runPure "unit/uuid-format-cases"
    (unitUUIDValid
      && unitUUIDAllZeros
      && unitUUIDAllF
      && unitUUIDUppercase
      && unitUUIDTooShort
      && unitUUIDNoHyphens
      && unitUUIDExtraChars
      && unitUUIDEmpty
      && unitUUIDValidateValid
      && unitUUIDValidateInvalid)
  hexCharProofs <- runPure "proof/is-hex-char"
    (isProven proofHexCharDigit
      && isProven proofHexCharA
      && isProven proofHexCharF
      && isProven proofHexCharUpperA
      && isProven proofHexCharG)

  let failures = timeUnitProofs + parseTimeUnitProofs + parseDurationUnits
        + roundtrip + monotonicity + zeroDur + bareMinutes
        + uuidUnits + hexCharProofs
  putStrLn ("failures: " ++ show failures)
  if failures == 0
    then pure ()
    else exitWith (ExitFailure 1)
