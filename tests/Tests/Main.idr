module Tests.Main

import Iris.Core.Frame
import Iris.Replay.Ttyrec.Parse
import System

toByte : Integer -> Bits8
toByte value = cast value

encodeU32LE : Nat -> List Bits8
encodeU32LE value =
  let n : Integer = cast value in
  [ toByte (n `mod` 256)
  , toByte ((n `div` 256) `mod` 256)
  , toByte ((n `div` 65536) `mod` 256)
  , toByte ((n `div` 16777216) `mod` 256)
  ]

encodeFrame : Frame -> List Bits8
encodeFrame frame =
  encodeU32LE (sec frame)
    ++ encodeU32LE (usec frame)
    ++ encodeU32LE (length (payload frame))
    ++ payload frame

sameFrame : Frame -> Frame -> Bool
sameFrame lhs rhs =
  sec lhs == sec rhs
    && usec lhs == usec rhs
    && payload lhs == payload rhs

sameFrames : List Frame -> List Frame -> Bool
sameFrames [] [] = True
sameFrames (x :: xs) (y :: ys) = sameFrame x y && sameFrames xs ys
sameFrames _ _ = False

parsedFramesEqual : List Frame -> Either ParseError (List Frame) -> Bool
parsedFramesEqual expected (Right actual) = sameFrames expected actual
parsedFramesEqual _ _ = False

isParseErrorAt : Nat -> Either ParseError (List Frame) -> Bool
isParseErrorAt expectedOffset (Left err) = offset err == expectedOffset
isParseErrorAt _ _ = False

unitFixedFrame : Bool
unitFixedFrame =
  let frame = MkFrame 1 123 [toByte 65, toByte 66, toByte 67]
   in parsedFramesEqual [frame] (parseBytes (encodeFrame frame))

unitEmptyPayload : Bool
unitEmptyPayload =
  let frame = MkFrame 7 900 []
   in parsedFramesEqual [frame] (parseBytes (encodeFrame frame))

unitMaxU32Fields : Bool
unitMaxU32Fields =
  let maxU32 = 4294967295
      frame = MkFrame maxU32 maxU32 []
   in parsedFramesEqual [frame] (parseBytes (encodeFrame frame))

unitTruncatedHeader : Bool
unitTruncatedHeader =
  isParseErrorAt 0 (parseBytes [toByte 1, toByte 2, toByte 3])

unitTruncatedPayload : Bool
unitTruncatedPayload =
  let bytes =
        encodeU32LE 10
          ++ encodeU32LE 20
          ++ encodeU32LE 4
          ++ [toByte 65, toByte 66]
   in isParseErrorAt 0 (parseBytes bytes)

unitMultiFrame : Bool
unitMultiFrame =
  let frame1 = MkFrame 1 10 [toByte 72, toByte 105]
      frame2 = MkFrame 2 20 [toByte 10]
      bytes = encodeFrame frame1 ++ encodeFrame frame2
   in parsedFramesEqual [frame1, frame2] (parseBytes bytes)

lcgModulus : Integer
lcgModulus = 4294967296

nextSeed : Integer -> Integer
nextSeed seed = (1664525 * seed + 1013904223) `mod` lcgModulus

randomU32 : Integer -> (Nat, Integer)
randomU32 seed =
  let s = nextSeed seed
   in (cast s, s)

randomPayloadLength : Integer -> (Nat, Integer)
randomPayloadLength seed =
  let s = nextSeed seed
   in (cast (s `mod` 32), s)

generatePayload : Nat -> Integer -> (List Bits8, Integer)
generatePayload Z seed = ([], seed)
generatePayload (S k) seed =
  let s = nextSeed seed
      byte = toByte (s `mod` 256)
      (rest, next) = generatePayload k s
   in (byte :: rest, next)

generateFrame : Integer -> (Frame, Integer)
generateFrame seed =
  let (secVal, s1) = randomU32 seed
      (usecVal, s2) = randomU32 s1
      (payloadLen, s3) = randomPayloadLength s2
      (payloadBytes, s4) = generatePayload payloadLen s3
   in (MkFrame secVal usecVal payloadBytes, s4)

generateFrames : Nat -> Integer -> (List Frame, Integer)
generateFrames Z seed = ([], seed)
generateFrames (S k) seed =
  let (frame, s1) = generateFrame seed
      (rest, s2) = generateFrames k s1
   in (frame :: rest, s2)

frameCountForSeed : Integer -> Nat
frameCountForSeed seed =
  let s = nextSeed seed
   in cast ((s `mod` 6) + 1)

propertyRoundtripSeed : Nat -> Bool
propertyRoundtripSeed seedNat =
  let seed = cast seedNat
      frameCount = frameCountForSeed seed
      (frames, _) = generateFrames frameCount seed
      bytes = concatMap encodeFrame frames
   in parsedFramesEqual frames (parseBytes bytes)

propertyRoundtripMany : Nat -> Bool
propertyRoundtripMany Z = propertyRoundtripSeed 0
propertyRoundtripMany (S k) =
  propertyRoundtripSeed (S k) && propertyRoundtripMany k

timestampLE : Frame -> Frame -> Bool
timestampLE lhs rhs =
  sec lhs < sec rhs
    || (sec lhs == sec rhs && usec lhs <= usec rhs)

timestampsNonDecreasing : List Frame -> Bool
timestampsNonDecreasing [] = True
timestampsNonDecreasing [_] = True
timestampsNonDecreasing (x :: y :: rest) =
  timestampLE x y && timestampsNonDecreasing (y :: rest)

integrationFixturePath : String
integrationFixturePath = "tests/fixtures/sample.ttyrec"

integrationRealFile : IO Bool
integrationRealFile = do
  parsed <- parseFile integrationFixturePath
  case parsed of
    Left _ => pure False
    Right frames =>
      pure (not (null frames) && timestampsNonDecreasing frames)

runPure : String -> Bool -> IO Nat
runPure name passed = do
  putStrLn ((if passed then "PASS " else "FAIL ") ++ name)
  pure (if passed then 0 else 1)

runIO : String -> IO Bool -> IO Nat
runIO name action = do
  passed <- action
  runPure name passed

roundsToSeedLimit : Nat -> Nat
roundsToSeedLimit Z = Z
roundsToSeedLimit (S k) = k

parsePropertyRounds : String -> Maybe Nat
parsePropertyRounds "10" = Just 10
parsePropertyRounds "50" = Just 50
parsePropertyRounds "200" = Just 200
parsePropertyRounds "1000" = Just 1000
parsePropertyRounds _ = Nothing

normalizeArgs : List String -> List String
normalizeArgs [] = []
normalizeArgs all@(arg0 :: rest) =
  if arg0 == "property-roundtrip"
    then all
    else rest

runPropertyOnly : Nat -> IO ()
runPropertyOnly rounds = do
  prop <- runPure
            ("property/roundtrip-" ++ show rounds ++ "-seeds")
            (propertyRoundtripMany (roundsToSeedLimit rounds))
  putStrLn ("failures: " ++ show prop)
  if prop == 0
    then pure ()
    else exitWith (ExitFailure 1)

runDefaultSuite : IO ()
runDefaultSuite = do
  unit1 <- runPure "unit/fixed-frame" unitFixedFrame
  unit2 <- runPure "unit/empty-payload" unitEmptyPayload
  unit3 <- runPure "unit/max-u32-fields" unitMaxU32Fields
  unit4 <- runPure "unit/truncated-header" unitTruncatedHeader
  unit5 <- runPure "unit/truncated-payload" unitTruncatedPayload
  unit6 <- runPure "unit/multi-frame" unitMultiFrame
  prop <- runPure "property/roundtrip-200-seeds" (propertyRoundtripMany 199)
  integ <- runIO "integration/fixture-parse" integrationRealFile

  let failures = unit1 + unit2 + unit3 + unit4 + unit5 + unit6 + prop + integ
  putStrLn ("failures: " ++ show failures)

  if failures == 0
    then pure ()
    else exitWith (ExitFailure 1)

public export
main : IO ()
main = do
  rawArgs <- getArgs
  let args = normalizeArgs rawArgs
  case args of
    ["property-roundtrip", roundsRaw] =>
      case parsePropertyRounds roundsRaw of
        Just rounds => runPropertyOnly rounds
        Nothing => do
          putStrLn "supported property rounds: 10, 50, 200, 1000"
          exitWith (ExitFailure 1)
    _ => runDefaultSuite
