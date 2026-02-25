module Iris.Core.Session

import Iris.Core.Window

||| A session containing named windows.
||| Window dimensions are existentially quantified — each window can differ.
public export
record Session where
  constructor MkSession
  name    : String
  windows : List (w : Nat ** h : Nat ** Window w h)
