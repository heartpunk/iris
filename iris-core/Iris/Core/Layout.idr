module Iris.Core.Layout

import Iris.Core.Pane

public export
data Direction = Horizontal | Vertical

||| A tiling layout with statically proven coverage.
||| Panes tile exactly: no overlap, full coverage of (width x height).
public export
data Layout : (width : Nat) -> (height : Nat) -> Type where
  ||| A single pane filling the entire area.
  Single : Pane width height -> Layout width height
  ||| Horizontal split: two layouts stacked vertically.
  HSplit : Layout width h1 -> Layout width h2 -> Layout width (h1 + h2)
  ||| Vertical split: two layouts side by side.
  VSplit : Layout w1 height -> Layout w2 height -> Layout (w1 + w2) height
