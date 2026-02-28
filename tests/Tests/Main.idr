module Tests.Main

import Data.Buffer
import Iris.Core.Frame
import Iris.Core.Parse
import Iris.Rec.Ttyrec.Write
import Iris.Replay.CLI
import Iris.Replay.Replay
import Iris.Replay.Ttyrec.Parse
import System
import System.File.Buffer

toByte : Integer -> Bits8
toByte value = cast value

byteToNat : Bits8 -> Nat
byteToNat b = cast (the Integer (cast b))

decodeU32LE4 : Bits8 -> Bits8 -> Bits8 -> Bits8 -> Nat
decodeU32LE4 b0 b1 b2 b3 =
  byteToNat b0
    + (byteToNat b1 * 256)
    + (byteToNat b2 * 65536)
    + (byteToNat b3 * 16777216)

decodeU32LE : List Bits8 -> Maybe Nat
decodeU32LE [b0, b1, b2, b3] = Just (decodeU32LE4 b0 b1 b2 b3)
decodeU32LE _ = Nothing

parseEncodedFrame : Frame -> Either ParseError (List Frame)
parseEncodedFrame frame =
  case encodeFrame frame of
    Left err => Left (MkParseError 0 err)
    Right bytes => parseBytes bytes

parseEncodedFrames : List Frame -> Either ParseError (List Frame)
parseEncodedFrames frames =
  case encodeFrames frames of
    Left err => Left (MkParseError 0 err)
    Right bytes => parseBytes bytes

listTake : Nat -> List a -> List a
listTake Z _ = []
listTake (S k) [] = []
listTake (S k) (x :: xs) = x :: listTake k xs

listDrop : Nat -> List a -> List a
listDrop Z xs = xs
listDrop (S k) [] = []
listDrop (S k) (_ :: xs) = listDrop k xs

sumEncodedSize : List Frame -> Nat
sumEncodedSize [] = 0
sumEncodedSize (frame :: rest) = (12 + length (payload frame)) + sumEncodedSize rest

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

-- Reference list indexing function. Used both as a proof target for frameAt
-- and as an oracle in property tests.
listAt : Nat -> List a -> Maybe a
listAt _ [] = Nothing
listAt Z (x :: _) = Just x
listAt (S k) (_ :: xs) = listAt k xs

-- Takes an equality proof; always True at runtime.
-- Compilation verifies the proof holds (type checker rejects Refl if not).
isProven : a = b -> Bool
isProven _ = True

-- Maybe Frame comparison without requiring Eq Frame.
maybeFrameEq : Maybe Frame -> Maybe Frame -> Bool
maybeFrameEq Nothing Nothing = True
maybeFrameEq (Just f) (Just g) = sameFrame f g
maybeFrameEq _ _ = False

unitFixedFrame : Bool
unitFixedFrame =
  let frame = MkFrame 1 123 [toByte 65, toByte 66, toByte 67]
   in parsedFramesEqual [frame] (parseEncodedFrame frame)

unitEmptyPayload : Bool
unitEmptyPayload =
  let frame = MkFrame 7 900 []
   in parsedFramesEqual [frame] (parseEncodedFrame frame)

unitMaxU32Fields : Bool
unitMaxU32Fields =
  let maxU32 = 4294967295
      frame = MkFrame maxU32 maxU32 []
   in parsedFramesEqual [frame] (parseEncodedFrame frame)

unitTruncatedHeader : Bool
unitTruncatedHeader =
  isParseErrorAt 0 (parseBytes [toByte 1, toByte 2, toByte 3])

unitTruncatedPayload : Bool
unitTruncatedPayload =
  case (do
    secBytes <- encodeU32LE 10
    usecBytes <- encodeU32LE 20
    lenBytes <- encodeU32LE 4
    pure (secBytes ++ usecBytes ++ lenBytes ++ [toByte 65, toByte 66])) of
    Left _ => False
    Right bytes => isParseErrorAt 0 (parseBytes bytes)

unitMultiFrame : Bool
unitMultiFrame =
  let frame1 = MkFrame 1 10 [toByte 72, toByte 105]
      frame2 = MkFrame 2 20 [toByte 10] in
    case (do
      bytes1 <- encodeFrame frame1
      bytes2 <- encodeFrame frame2
      pure (bytes1 ++ bytes2)) of
      Left _ => False
      Right bytes => parsedFramesEqual [frame1, frame2] (parseBytes bytes)

unitTimestampFormatting : Bool
unitTimestampFormatting =
  formatTimestampMicros 10000100 == "10.000100"
    && formatTimestampMicros 1000000 == "1.000000"
    && formatTimestampMicros 100 == "0.000100"

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

propertyFrameCountSeed : Nat -> Bool
propertyFrameCountSeed seedNat =
  let seed = cast seedNat
      frameCount = frameCountForSeed seed
      (frames, _) = generateFrames frameCount seed
   in case parseEncodedFrames frames of
        Left _ => False
        Right parsed => length parsed == length frames

propertyU32RoundtripSeed : Nat -> Bool
propertyU32RoundtripSeed seedNat =
  let (value, _) = randomU32 (cast seedNat)
   in case encodeU32LE value of
        Left _ => False
        Right encoded => decodeU32LE encoded == Just value

propertyU32OutOfRangeSeed : Nat -> Bool
propertyU32OutOfRangeSeed seedNat =
  let overflowValue = 4294967296 + seedNat
   in case encodeU32LE overflowValue of
        Left _ => True
        Right _ => False

propertyOrderingSeed : Nat -> Bool
propertyOrderingSeed seedNat =
  let seed = cast seedNat
      frameCount = frameCountForSeed seed
      (frames, _) = generateFrames frameCount seed
   in case parseEncodedFrames frames of
        Left _ => False
        Right parsed => sameFrames frames parsed

validatePayloadLens : List Frame -> List Bits8 -> Bool
validatePayloadLens [] [] = True
validatePayloadLens [] _ = False
validatePayloadLens (_ :: _) [] = False
validatePayloadLens (frame :: restFrames) bytes =
  case bytes of
    _ :: _ :: _ :: _ :: _ :: _ :: _ :: _ :: l0 :: l1 :: l2 :: l3 :: restBytes =>
      let expectedLen = length (payload frame)
          headerLen = decodeU32LE4 l0 l1 l2 l3
          payloadPart = listTake headerLen restBytes
       in headerLen == expectedLen
            && length payloadPart == headerLen
            && validatePayloadLens restFrames (listDrop headerLen restBytes)
    _ => False

propertyPayloadLenMatchesHeaderSeed : Nat -> Bool
propertyPayloadLenMatchesHeaderSeed seedNat =
  let seed = cast seedNat
      frameCount = frameCountForSeed seed
      (frames, _) = generateFrames frameCount seed in
    case encodeFrames frames of
      Left _ => False
      Right bytes => validatePayloadLens frames bytes

validateHeaderBytes : List Frame -> List Bits8 -> Bool
validateHeaderBytes [] [] = True
validateHeaderBytes [] _ = False
validateHeaderBytes (_ :: _) [] = False
validateHeaderBytes (frame :: restFrames) bytes =
  case bytes of
    s0 :: s1 :: s2 :: s3 :: u0 :: u1 :: u2 :: u3 :: l0 :: l1 :: l2 :: l3 :: restBytes =>
      let secBytes = [s0, s1, s2, s3]
          usecBytes = [u0, u1, u2, u3]
          lenBytes = [l0, l1, l2, l3]
          expectedLen = length (payload frame)
          payloadPart = listTake expectedLen restBytes in
        case (encodeU32LE (sec frame), encodeU32LE (usec frame), encodeU32LE expectedLen) of
          (Right expectedSec, Right expectedUsec, Right expectedLenBytes) =>
            secBytes == expectedSec
              && usecBytes == expectedUsec
              && lenBytes == expectedLenBytes
              && length payloadPart == expectedLen
              && validateHeaderBytes restFrames (listDrop expectedLen restBytes)
          _ => False
    _ => False

propertyHeaderBytesSeed : Nat -> Bool
propertyHeaderBytesSeed seedNat =
  let seed = cast seedNat
      frameCount = frameCountForSeed seed
      (frames, _) = generateFrames frameCount seed in
    case encodeFrames frames of
      Left _ => False
      Right bytes => validateHeaderBytes frames bytes

propertySizeLawSeed : Nat -> Bool
propertySizeLawSeed seedNat =
  let seed = cast seedNat
      frameCount = frameCountForSeed seed
      (frames, _) = generateFrames frameCount seed in
    case encodeFrames frames of
      Left _ => False
      Right bytes => length bytes == sumEncodedSize frames

propertyConcatLawSeed : Nat -> Bool
propertyConcatLawSeed seedNat =
  let seedA = cast seedNat
      seedB = cast (S seedNat)
      countA = frameCountForSeed seedA
      countB = frameCountForSeed seedB
      (framesA, _) = generateFrames countA seedA
      (framesB, _) = generateFrames countB seedB in
    case (encodeFrames (framesA ++ framesB), encodeFrames framesA, encodeFrames framesB) of
      (Right allBytes, Right bytesA, Right bytesB) => allBytes == (bytesA ++ bytesB)
      _ => False

allBytesFrom : Integer -> List Bits8
allBytesFrom n =
  if n >= 256
    then []
    else toByte n :: allBytesFrom (n + 1)

allByteValues : List Bits8
allByteValues = allBytesFrom 0

propertyBinaryTransparencyAllBytes : Bool
propertyBinaryTransparencyAllBytes =
  let frame = MkFrame 77 12 allByteValues
   in case parseEncodedFrames [frame] of
        Left _ => False
        Right [parsed] => payload parsed == allByteValues
        Right _ => False

-- Reference implementation: naive left-to-right payload concatenation.
-- Used to verify collectPayloads' double-reverse accumulation idiom.
concatPayloads : List Frame -> List Bits8
concatPayloads [] = []
concatPayloads (frame :: rest) = payload frame ++ concatPayloads rest

-- Property: collectPayloads == naive concatenation of payloads for any frame list.
propertyCollectPayloadsConcat : Nat -> Bool
propertyCollectPayloadsConcat seedNat =
  let seed = cast seedNat
      frameCount = frameCountForSeed seed
      (frames, _) = generateFrames frameCount seed
   in collectPayloads frames == concatPayloads frames

-- ==========================================================================
-- frameAt proofs (compile-time verified by Idris 2's type checker)
-- ==========================================================================

-- Proof: frameAt on the empty list is Nothing for all indices.
frameAtNil : (idx : Nat) -> frameAt idx (the (List Frame) []) = Nothing
frameAtNil _ = Refl

-- Proof: frameAt Z returns the head of a non-empty list.
frameAtHead : (f : Frame) -> (fs : List Frame) -> frameAt Z (f :: fs) = Just f
frameAtHead _ _ = Refl

-- Proof (structural induction): frameAt is definitionally equal to the
-- reference listAt on all inputs.  This is the correctness theorem.
frameAtIsListAt : (idx : Nat) -> (frames : List Frame) ->
                  frameAt idx frames = listAt idx frames
frameAtIsListAt _ [] = Refl
frameAtIsListAt Z (_ :: _) = Refl
frameAtIsListAt (S k) (_ :: rest) = frameAtIsListAt k rest

-- ==========================================================================
-- parseNat proofs (compile-time verified by computation)
-- Idris evaluates parseNat on each literal and confirms the result matches.
-- If any Refl is wrong the file will not compile.
-- ==========================================================================

proofParseNatEmpty : parseNat "" = Nothing
proofParseNatEmpty = Refl

proofParseNatZero : parseNat "0" = Just 0
proofParseNatZero = Refl

proofParseNatOne : parseNat "1" = Just 1
proofParseNatOne = Refl

proofParseNatNine : parseNat "9" = Just 9
proofParseNatNine = Refl

proofParseNatFortytwo : parseNat "42" = Just 42
proofParseNatFortytwo = Refl

proofParseNatHundred : parseNat "100" = Just 100
proofParseNatHundred = Refl

-- Four-digit value: exercises multi-step foldl accumulation without
-- blowing up the type checker (Nat is unary, so 10-digit values hang).
proofParseNat9999 : parseNat "9999" = Just 9999
proofParseNat9999 = Refl

-- Leading zeros parse to the numeric value (not rejected, not misread).
proofParseNatLeadingZeros : parseNat "007" = Just 7
proofParseNatLeadingZeros = Refl

-- Non-digit characters rejected at every position.
proofParseNatAlpha : parseNat "a" = Nothing
proofParseNatAlpha = Refl

proofParseNatMixed : parseNat "12x3" = Nothing
proofParseNatMixed = Refl

proofParseNatNegative : parseNat "-1" = Nothing
proofParseNatNegative = Refl

proofParseNatDot : parseNat "3.14" = Nothing
proofParseNatDot = Refl

proofParseNatSpace : parseNat "1 2" = Nothing
proofParseNatSpace = Refl

-- ==========================================================================
-- frameAt property tests
-- ==========================================================================

-- frameAt and listAt agree for any (idx, frames) pair — runtime sampling
-- across LCG seeds.  Logically redundant with frameAtIsListAt but covers
-- the runtime code path.
propertyFrameAtEqualsListAt : Nat -> Bool
propertyFrameAtEqualsListAt seedNat =
  let seed = cast seedNat
      frameCount = frameCountForSeed seed
      (frames, s1) = generateFrames frameCount seed
      (idxNat, _) = randomU32 s1
      idx = cast idxNat
   in maybeFrameEq (frameAt idx frames) (listAt idx frames)

-- frameAt exactly at length is always Nothing (one past end).
propertyFrameAtExactlyOutOfBounds : Nat -> Bool
propertyFrameAtExactlyOutOfBounds seedNat =
  let seed = cast seedNat
      frameCount = frameCountForSeed seed
      (frames, _) = generateFrames frameCount seed
   in case frameAt (length frames) frames of
            Nothing => True
            Just _ => False

-- For a valid in-bounds index, frameAt and listAt agree.
propertyFrameAtInBoundsMatchesListAt : Nat -> Bool
propertyFrameAtInBoundsMatchesListAt seedNat =
  let seed = cast seedNat
      frameCount = frameCountForSeed seed
      (frames, s1) = generateFrames frameCount seed
      (idxNat, _) = randomU32 s1
      idx = cast (the Integer (cast idxNat `mod` cast frameCount))
   in maybeFrameEq (frameAt idx frames) (listAt idx frames)

-- ==========================================================================
-- parseNat property tests
-- ==========================================================================

-- Roundtrip: parsing the decimal representation of any Nat recovers it.
propertyParseNatRoundtrip : Nat -> Bool
propertyParseNatRoundtrip seedNat =
  let (n, _) = randomU32 (cast seedNat)
   in parseNat (show n) == Just n

-- Appending a non-digit to any valid decimal string gives Nothing.
propertyParseNatNonDigitSuffix : Nat -> Bool
propertyParseNatNonDigitSuffix seedNat =
  let (n, _) = randomU32 (cast seedNat)
   in parseNat (show n ++ "!") == Nothing

readBufferBytes : Buffer -> Int -> IO (List Bits8)
readBufferBytes buffer size = go 0 []
  where
    go : Int -> List Bits8 -> IO (List Bits8)
    go index acc =
      if index >= size
        then pure (reverse acc)
        else do
          byte <- getBits8 buffer index
          go (index + 1) (byte :: acc)

readFileBytes : String -> IO (Either String (List Bits8))
readFileBytes path = do
  loaded <- createBufferFromFile path
  case loaded of
    Left err => pure (Left ("failed to read file bytes: " ++ show err))
    Right buffer => do
      size <- rawSize buffer
      bytes <- readBufferBytes buffer size
      pure (Right bytes)

propertyWriteFidelity : IO Bool
propertyWriteFidelity = do
  let frames =
        [ MkFrame 3 1 allByteValues
        , MkFrame 3 2 [toByte 0, toByte 1, toByte 2, toByte 3]
        ]
  case encodeFrames frames of
    Left _ => pure False
    Right expected => do
      wrote <- writeTtyrec "/tmp/iris-rec-write-fidelity.ttyrec" frames
      case wrote of
        Left _ => pure False
        Right () => do
          onDisk <- readFileBytes "/tmp/iris-rec-write-fidelity.ttyrec"
          case onDisk of
            Left _ => pure False
            Right bytes => pure (bytes == expected)

-- Property: raw-dump selects a single frame's bytes byte-exact.
-- Write two frames with distinct payloads, parse back, verify each frame's
-- payload is preserved independently (full byte range in frame 1).
rawDumpRoundtripPath : String
rawDumpRoundtripPath = "/tmp/iris-replay-raw-dump-roundtrip.ttyrec"

propertyRawDumpRoundtrip : IO Bool
propertyRawDumpRoundtrip = do
  let frame0 = MkFrame 1 100 [toByte 10, toByte 20, toByte 30]
      frame1 = MkFrame 2 200 allByteValues
      frames = [frame0, frame1]
  wrote <- writeTtyrec rawDumpRoundtripPath frames
  case wrote of
    Left _ => pure False
    Right () => do
      parsed <- parseFile rawDumpRoundtripPath Nothing
      case parsed of
        Left _ => pure False
        Right [pf0, pf1] =>
          -- Each frame's payload must survive write -> parse independently
          pure (payload pf0 == payload frame0 && payload pf1 == payload frame1)
        Right _ => pure False

propertyRoundtripSeed : Nat -> Bool
propertyRoundtripSeed seedNat =
  let seed = cast seedNat
      frameCount = frameCountForSeed seed
      (frames, _) = generateFrames frameCount seed in
    case encodeFrames frames of
      Left _ => False
      Right bytes => parsedFramesEqual frames (parseBytes bytes)

propertyMany : (Nat -> Bool) -> Nat -> Bool
propertyMany prop Z = prop 0
propertyMany prop (S k) = prop (S k) && propertyMany prop k

propertyRoundtripMany : Nat -> Bool
propertyRoundtripMany rounds = propertyMany propertyRoundtripSeed rounds

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
  parsed <- parseFile integrationFixturePath Nothing
  case parsed of
    Left _ => pure False
    Right frames =>
      pure (not (null frames) && timestampsNonDecreasing frames)

writerRoundtripPath : String
writerRoundtripPath = "/tmp/iris-rec-roundtrip.ttyrec"

writerRoundtripFile : IO Bool
writerRoundtripFile = do
  let frame1 = MkFrame 10 1 [toByte 65, toByte 66, toByte 67]
  let frame2 = MkFrame 10 2 [toByte 10]
  let frames = [frame1, frame2]
  wrote <- writeTtyrec writerRoundtripPath frames
  case wrote of
    Left _ => pure False
    Right () => do
      parsed <- parseFile writerRoundtripPath Nothing
      pure (parsedFramesEqual frames parsed)

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

runPropertySuite : Nat -> IO Nat
runPropertySuite rounds = do
  let limit = roundsToSeedLimit rounds
  frameCount <- runPure
                  ("property/frame-count-preservation-" ++ show rounds ++ "-seeds")
                  (propertyMany propertyFrameCountSeed limit)
  leRoundtrip <- runPure
                   ("property/le-u32-roundtrip-" ++ show rounds ++ "-seeds")
                   (propertyMany propertyU32RoundtripSeed limit)
  leOutOfRange <- runPure
                    ("property/le-u32-out-of-range-rejected-" ++ show rounds ++ "-seeds")
                    (propertyMany propertyU32OutOfRangeSeed limit)
  ordering <- runPure
                ("property/order-preservation-" ++ show rounds ++ "-seeds")
                (propertyMany propertyOrderingSeed limit)
  payloadLen <- runPure
                  ("property/payload-len-matches-header-" ++ show rounds ++ "-seeds")
                  (propertyMany propertyPayloadLenMatchesHeaderSeed limit)
  headerBytes <- runPure
                   ("property/header-byte-spotcheck-" ++ show rounds ++ "-seeds")
                   (propertyMany propertyHeaderBytesSeed limit)
  sizeLaw <- runPure
               ("property/size-law-" ++ show rounds ++ "-seeds")
               (propertyMany propertySizeLawSeed limit)
  concatLaw <- runPure
                 ("property/concat-law-" ++ show rounds ++ "-seeds")
                 (propertyMany propertyConcatLawSeed limit)
  binaryTransparency <- runPure
                          "property/binary-transparency-all-bytes"
                          propertyBinaryTransparencyAllBytes
  collectConcat <- runPure
                     ("property/collect-payloads-concat-" ++ show rounds ++ "-seeds")
                     (propertyMany propertyCollectPayloadsConcat limit)
  writeFidelity <- runIO
                     "property/write-fidelity-disk-vs-encode"
                     propertyWriteFidelity
  -- Proofs: compile-time verified, reported here so they appear in output.
  frameAtProofs <- runPure "proof/frame-at-is-list-at"
                     (isProven (frameAtNil 0) && isProven (frameAtNil 99)
                       && isProven (frameAtHead (MkFrame 0 0 []) [])
                       && isProven (frameAtIsListAt 0 [])
                       && isProven (frameAtIsListAt 3 []))
  parseNatProofs <- runPure "proof/parse-nat-computed-cases"
                      (isProven proofParseNatEmpty
                        && isProven proofParseNatZero
                        && isProven proofParseNatOne
                        && isProven proofParseNatNine
                        && isProven proofParseNatFortytwo
                        && isProven proofParseNatHundred
                        && isProven proofParseNat9999
                        && isProven proofParseNatLeadingZeros
                        && isProven proofParseNatAlpha
                        && isProven proofParseNatMixed
                        && isProven proofParseNatNegative
                        && isProven proofParseNatDot
                        && isProven proofParseNatSpace)
  -- Property tests for frameAt
  frameAtListAt <- runPure
                     ("property/frame-at-equals-list-at-" ++ show rounds ++ "-seeds")
                     (propertyMany propertyFrameAtEqualsListAt limit)
  frameAtOob <- runPure
                  ("property/frame-at-out-of-bounds-" ++ show rounds ++ "-seeds")
                  (propertyMany propertyFrameAtExactlyOutOfBounds limit)
  frameAtInBounds <- runPure
                       ("property/frame-at-in-bounds-" ++ show rounds ++ "-seeds")
                       (propertyMany propertyFrameAtInBoundsMatchesListAt limit)
  -- Property tests for parseNat
  parseNatRoundtrip <- runPure
                         ("property/parse-nat-roundtrip-" ++ show rounds ++ "-seeds")
                         (propertyMany propertyParseNatRoundtrip limit)
  parseNatNonDigit <- runPure
                        ("property/parse-nat-non-digit-suffix-" ++ show rounds ++ "-seeds")
                        (propertyMany propertyParseNatNonDigitSuffix limit)

  pure
    (frameCount + leRoundtrip + leOutOfRange + ordering + payloadLen + headerBytes
      + sizeLaw + concatLaw + binaryTransparency + collectConcat + writeFidelity
      + frameAtProofs + parseNatProofs
      + frameAtListAt + frameAtOob + frameAtInBounds
      + parseNatRoundtrip + parseNatNonDigit)

runPropertyOnly : Nat -> IO ()
runPropertyOnly rounds = do
  roundtrip <- runPure
                 ("property/roundtrip-iris-rec-replay-" ++ show rounds ++ "-seeds")
                 (propertyRoundtripMany (roundsToSeedLimit rounds))
  other <- runPropertySuite rounds
  let failures = roundtrip + other
  putStrLn ("failures: " ++ show failures)
  if failures == 0
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
  unit7 <- runPure "unit/timestamp-format-zero-padded" unitTimestampFormatting
  roundtrip <- runPure "property/roundtrip-iris-rec-replay-200-seeds" (propertyRoundtripMany 199)
  prop <- runPropertySuite 200
  writeRoundtrip <- runIO "roundtrip/write-file-then-parse" writerRoundtripFile
  rawDumpRoundtrip <- runIO "roundtrip/raw-dump-parse-collect-payloads" propertyRawDumpRoundtrip
  integ <- runIO "integration/fixture-parse" integrationRealFile

  let failures =
        unit1 + unit2 + unit3 + unit4 + unit5 + unit6 + unit7
          + roundtrip + prop + writeRoundtrip + rawDumpRoundtrip + integ
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
