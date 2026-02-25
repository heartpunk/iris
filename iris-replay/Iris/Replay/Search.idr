module Iris.Replay.Search

import Iris.Core.Frame

public export
record FrameMatch where
  constructor MkFrameMatch
  frameIndex : Nat
  frame      : Frame

public export
searchFrames : String -> List Frame -> List FrameMatch
searchFrames _ _ = []
