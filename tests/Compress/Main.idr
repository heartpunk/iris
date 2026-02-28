module Compress.Main

import Iris.Compress.TimeUnit
import Iris.Compress.UUID
import Iris.Compress.FileClass
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

-- ==========================================================================
-- FileClass unit tests
-- ==========================================================================

-- Helper: compare FileClass values.
fileClassEq : FileClass -> FileClass -> Bool
fileClassEq (RawTtyrec a) (RawTtyrec b) = uuid a == uuid b
fileClassEq (ZstTtyrec a) (ZstTtyrec b) = uuid a == uuid b
fileClassEq (AlreadyCompressed a) (AlreadyCompressed b) = uuid a == uuid b
fileClassEq (Unrecognized a) (Unrecognized b) = a == b
fileClassEq _ _ = False

unitClassifyRaw : Bool
unitClassifyRaw = fileClassEq
  (classifyFile "550e8400-e29b-41d4-a716-446655440000")
  (RawTtyrec (MkValidUUID "550e8400-e29b-41d4-a716-446655440000"))

unitClassifyZst : Bool
unitClassifyZst = fileClassEq
  (classifyFile "550e8400-e29b-41d4-a716-446655440000.ttyrec.zst")
  (ZstTtyrec (MkValidUUID "550e8400-e29b-41d4-a716-446655440000"))

unitClassifyLz : Bool
unitClassifyLz = fileClassEq
  (classifyFile "550e8400-e29b-41d4-a716-446655440000.lz")
  (AlreadyCompressed (MkValidUUID "550e8400-e29b-41d4-a716-446655440000"))

unitClassifyBadLz : Bool
unitClassifyBadLz = fileClassEq
  (classifyFile "not-a-uuid.lz")
  (Unrecognized "not-a-uuid.lz")

unitClassifyBadZst : Bool
unitClassifyBadZst = fileClassEq
  (classifyFile "not-a-uuid.ttyrec.zst")
  (Unrecognized "not-a-uuid.ttyrec.zst")

unitClassifyRandom : Bool
unitClassifyRandom = fileClassEq
  (classifyFile "random-file.txt")
  (Unrecognized "random-file.txt")

unitClassifyEmpty : Bool
unitClassifyEmpty = fileClassEq
  (classifyFile "")
  (Unrecognized "")

unitClassifyHidden : Bool
unitClassifyHidden = fileClassEq
  (classifyFile ".hidden-file")
  (Unrecognized ".hidden-file")

-- ==========================================================================
-- UUID property tests
-- ==========================================================================

-- Generate a hex character from a seed.
hexCharAt : Integer -> Char
hexCharAt n =
  let idx = n `mod` 16
   in if idx < 10
        then chr (cast idx + ord '0')
        else chr (cast (idx - 10) + ord 'a')

-- Generate a hex string of given length from a seed.
genHexStr : Nat -> Integer -> (String, Integer)
genHexStr Z seed = ("", seed)
genHexStr (S k) seed =
  let s = nextSeed seed
      c = hexCharAt s
      (rest, s2) = genHexStr k s
   in (strCons c rest, s2)

-- Generate a valid UUID string from a seed.
genUUID : Integer -> (String, Integer)
genUUID seed =
  let (p1, s1) = genHexStr 8 seed
      (p2, s2) = genHexStr 4 s1
      (p3, s3) = genHexStr 4 s2
      (p4, s4) = genHexStr 4 s3
      (p5, s5) = genHexStr 12 s4
   in (p1 ++ "-" ++ p2 ++ "-" ++ p3 ++ "-" ++ p4 ++ "-" ++ p5, s5)

-- Property: generated valid UUID strings pass isUUIDFormat.
propertyGenUUIDValid : Nat -> Bool
propertyGenUUIDValid seedNat =
  let (u, _) = genUUID (cast seedNat)
   in isUUIDFormat u

-- Property: validateUUID roundtrip — validated UUID's string matches input.
propertyValidateRoundtrip : Nat -> Bool
propertyValidateRoundtrip seedNat =
  let (u, _) = genUUID (cast seedNat)
   in case validateUUID u of
        Just v  => uuid v == u
        Nothing => False

-- Property: non-hex characters cause rejection.
propertyNonHexRejected : Nat -> Bool
propertyNonHexRejected seedNat =
  let (u, s1) = genUUID (cast seedNat)
      s2 = nextSeed s1
      -- Pick a position in the UUID (0-35), skip hyphens at 8,13,18,23
      pos = cast {to=Nat} (s2 `mod` 32)
      chars = unpack u
      -- Insert a 'G' (non-hex uppercase) at a hex position
      replaced = replaceAt pos chars
   in not (isUUIDFormat (pack replaced))
  where
    replaceAt : Nat -> List Char -> List Char
    replaceAt Z [] = []
    replaceAt Z (_ :: rest) = 'G' :: rest
    replaceAt (S k) [] = []
    replaceAt (S k) (c :: rest) =
      if c == '-'
        then c :: replaceAt (S k) rest  -- skip hyphens, don't count them
        else c :: replaceAt k rest

-- ==========================================================================
-- FileClass property tests
-- ==========================================================================

-- Property: classifyFile on a bare generated UUID is RawTtyrec.
propertyClassifyRaw : Nat -> Bool
propertyClassifyRaw seedNat =
  let (u, _) = genUUID (cast seedNat)
   in case classifyFile u of
        RawTtyrec _ => True
        _ => False

-- Property: classifyFile on UUID.ttyrec.zst is ZstTtyrec.
propertyClassifyZst : Nat -> Bool
propertyClassifyZst seedNat =
  let (u, _) = genUUID (cast seedNat)
   in case classifyFile (u ++ ".ttyrec.zst") of
        ZstTtyrec _ => True
        _ => False

-- Property: classifyFile on UUID.lz is AlreadyCompressed.
propertyClassifyLz : Nat -> Bool
propertyClassifyLz seedNat =
  let (u, _) = genUUID (cast seedNat)
   in case classifyFile (u ++ ".lz") of
        AlreadyCompressed _ => True
        _ => False

-- Property: classifyFile preserves the UUID in all recognized variants.
propertyClassifyPreservesUUID : Nat -> Bool
propertyClassifyPreservesUUID seedNat =
  let (u, _) = genUUID (cast seedNat)
   in case classifyFile u of
        RawTtyrec v => uuid v == u
        _ => False
      && case classifyFile (u ++ ".ttyrec.zst") of
           ZstTtyrec v => uuid v == u
           _ => False
      && case classifyFile (u ++ ".lz") of
           AlreadyCompressed v => uuid v == u
           _ => False

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

  fileClassUnits <- runPure "unit/file-class-cases"
    (unitClassifyRaw
      && unitClassifyZst
      && unitClassifyLz
      && unitClassifyBadLz
      && unitClassifyBadZst
      && unitClassifyRandom
      && unitClassifyEmpty
      && unitClassifyHidden)

  genValid <- runPure "property/gen-uuid-valid-200-seeds"
    (propertyMany propertyGenUUIDValid rounds)
  validateRt <- runPure "property/validate-uuid-roundtrip-200-seeds"
    (propertyMany propertyValidateRoundtrip rounds)
  nonHexRej <- runPure "property/non-hex-rejected-200-seeds"
    (propertyMany propertyNonHexRejected rounds)

  classifyRaw <- runPure "property/classify-raw-200-seeds"
    (propertyMany propertyClassifyRaw rounds)
  classifyZst <- runPure "property/classify-zst-200-seeds"
    (propertyMany propertyClassifyZst rounds)
  classifyLz <- runPure "property/classify-lz-200-seeds"
    (propertyMany propertyClassifyLz rounds)
  classifyUUID <- runPure "property/classify-preserves-uuid-200-seeds"
    (propertyMany propertyClassifyPreservesUUID rounds)

  let failures = timeUnitProofs + parseTimeUnitProofs + parseDurationUnits
        + roundtrip + monotonicity + zeroDur + bareMinutes
        + uuidUnits + hexCharProofs
        + fileClassUnits
        + genValid + validateRt + nonHexRej
        + classifyRaw + classifyZst + classifyLz + classifyUUID
  putStrLn ("failures: " ++ show failures)
  if failures == 0
    then pure ()
    else exitWith (ExitFailure 1)
