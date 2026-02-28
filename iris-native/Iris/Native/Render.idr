module Iris.Native.Render

import Data.List
import Data.Nat
import Data.String
import Iris.Native.State

||| ANSI escape: move cursor to (row, col) — 1-indexed.
moveTo : Nat -> Nat -> String
moveTo row col = "\ESC[" ++ show (row + 1) ++ ";" ++ show (col + 1) ++ "H"

||| ANSI escape: clear entire screen.
export
clearScreen : String
clearScreen = "\ESC[2J"

||| ANSI escape: hide cursor.
export
hideCursor : String
hideCursor = "\ESC[?25l"

||| ANSI escape: show cursor.
export
showCursor : String
showCursor = "\ESC[?25h"

||| ANSI escape: enter alternate screen buffer.
export
enterAltScreen : String
enterAltScreen = "\ESC[?1049h"

||| ANSI escape: exit alternate screen buffer.
export
exitAltScreen : String
exitAltScreen = "\ESC[?1049l"

||| Pad or truncate a string to exactly n characters.
padOrTruncate : Nat -> String -> String
padOrTruncate n s =
  let len = length s
  in if len >= n
    then substr 0 n s
    else s ++ pack (replicate (minus n len) ' ')

||| Render a horizontal border line of dashes at the given row.
renderHBorder : (y : Nat) -> (x : Nat) -> (w : Nat) -> String
renderHBorder y x w = moveTo y x ++ pack (replicate w '-')

||| Render a vertical border line at column x from y to y+h.
renderVBorder : (x : Nat) -> (y : Nat) -> (h : Nat) -> String
renderVBorder x y 0 = ""
renderVBorder x y (S n) = moveTo y x ++ "|" ++ renderVBorder x (S y) n

||| Get the last n lines from a buffer (most recent lines).
takeLast : Nat -> List a -> List a
takeLast n xs = drop (minus (length xs) n) xs

||| Generate a list [0, 1, ..., n-1].
range : Nat -> List Nat
range 0 = []
range (S n) = range n ++ [n]

||| Render a single pane's content into its screen rectangle.
renderPane : PaneState -> String
renderPane ps =
  let visibleLines = takeLast ps.screenH ps.buffer
      padded = take ps.screenH (visibleLines ++ replicate ps.screenH "")
      indexed = zip (range ps.screenH) padded
      renderLine : (Nat, String) -> String
      renderLine (row, line) = moveTo (ps.screenY + row) ps.screenX
                               ++ padOrTruncate ps.screenW line
  in concatMap renderLine indexed

||| Render borders between panes. Borders go at split boundaries.
export
renderBorders : List PaneRect -> String
renderBorders [] = ""
renderBorders [_] = ""
renderBorders rects =
  let hBorders = findHBorders rects
      vBorders = findVBorders rects
  in concat hBorders ++ concat vBorders
  where
    findHBorders : List PaneRect -> List String
    findHBorders [] = []
    findHBorders (r :: rs) =
      let below = filter (\r2 => r2.y == r.y + r.h && r2.x == r.x) rs
          borders = map (\r2 => renderHBorder (r.y + r.h) r.x (max r.w r2.w)) below
      in borders ++ findHBorders rs

    findVBorders : List PaneRect -> List String
    findVBorders [] = []
    findVBorders (r :: rs) =
      let rightOf = filter (\r2 => r2.x == r.x + r.w && r2.y == r.y) rs
          borders = map (\r2 => renderVBorder (r.x + r.w) r.y (max r.h r2.h)) rightOf
      in borders ++ findVBorders rs

||| Render all dirty panes and return the combined output string.
export
renderDirtyPanes : List PaneState -> String
renderDirtyPanes panes =
  concatMap renderPane (filter (.dirty) panes)

||| Full screen render: clear, render all panes, render borders.
export
renderFull : List PaneState -> List PaneRect -> String
renderFull panes rects =
  hideCursor ++ clearScreen
  ++ concatMap renderPane panes
  ++ renderBorders rects
  ++ showCursor
