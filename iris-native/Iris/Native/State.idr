module Iris.Native.State

import Data.IORef

||| Runtime pane state: PTY fd, output buffer, screen position.
public export
record PaneState where
  constructor MkPaneState
  paneId   : Nat
  ptyFd    : Int
  childPid : Int
  buffer   : List String   -- line buffer (most recent last)
  dirty    : Bool
  closed   : Bool
  -- Screen rectangle (set during layout flatten)
  screenX  : Nat
  screenY  : Nat
  screenW  : Nat
  screenH  : Nat

||| Runtime layout mirror of iris-core's Layout GADT.
||| Carries runtime dimensions and pane IDs.
public export
data AnnotatedLayout : (w : Nat) -> (h : Nat) -> Type where
  ASingle : (paneId : Nat) -> (w : Nat) -> (h : Nat) -> AnnotatedLayout w h
  AHSplit  : (h1 : Nat) -> AnnotatedLayout w h1 -> AnnotatedLayout w h2
          -> AnnotatedLayout w (h1 + h2)
  AVSplit  : (w1 : Nat) -> AnnotatedLayout w1 h -> AnnotatedLayout w2 h
          -> AnnotatedLayout (w1 + w2) h

||| A screen rectangle for a pane.
public export
record PaneRect where
  constructor MkPaneRect
  paneId : Nat
  x      : Nat
  y      : Nat
  w      : Nat
  h      : Nat

||| Flatten a layout into a list of screen rectangles.
export
flattenLayout : (offX : Nat) -> (offY : Nat) -> AnnotatedLayout w h -> List PaneRect
flattenLayout offX offY (ASingle pid pw ph) =
  [MkPaneRect pid offX offY pw ph]
flattenLayout offX offY (AHSplit h1 top bottom) =
  flattenLayout offX offY top ++ flattenLayout offX (offY + h1) bottom
flattenLayout offX offY (AVSplit w1 left right) =
  flattenLayout offX offY left ++ flattenLayout (offX + w1) offY right

||| Mux-wide runtime state.
public export
record MuxState where
  constructor MkMuxState
  panes      : List PaneState
  activePaneId : Nat
  nextPaneId : Nat
  termCols   : Nat
  termRows   : Nat
  ctlPipePath : String
  ctlPipeFd  : Int
  running    : Bool
