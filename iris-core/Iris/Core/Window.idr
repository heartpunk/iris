module Iris.Core.Window

import Iris.Core.Layout

||| A window with a tiling layout of known dimensions.
public export
record Window (width : Nat) (height : Nat) where
  constructor MkWindow
  name   : String
  layout : Layout width height
