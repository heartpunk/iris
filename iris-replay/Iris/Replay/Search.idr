module Iris.Replay.Search

import Iris.Core.Frame

public export
record FrameMatch where
  constructor MkFrameMatch
  frameIndex : Nat
  frame      : Frame

byteToChar : Bits8 -> Char
byteToChar b = chr (cast (the Integer (cast b)))

payloadText : Frame -> String
payloadText frame = pack (map byteToChar (payload frame))

startsWithChars : List Char -> List Char -> Bool
startsWithChars [] _ = True
startsWithChars (_ :: _) [] = False
startsWithChars (x :: xs) (y :: ys) = x == y && startsWithChars xs ys

containsChars : List Char -> List Char -> Bool
containsChars [] _ = True
containsChars (_ :: _) [] = False
containsChars needle haystack@(_ :: rest) =
  startsWithChars needle haystack || containsChars needle rest

containsText : String -> String -> Bool
containsText query text = containsChars (unpack query) (unpack text)

searchAt : Nat -> String -> List Frame -> List FrameMatch
searchAt _ _ [] = []
searchAt idx query (frame :: rest) =
  if containsText query (payloadText frame)
    then MkFrameMatch idx frame :: searchAt (S idx) query rest
    else searchAt (S idx) query rest

public export
searchFrames : String -> List Frame -> List FrameMatch
searchFrames query frames = searchAt 0 query frames
