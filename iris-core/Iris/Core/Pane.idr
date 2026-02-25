module Iris.Core.Pane

||| A terminal pane with statically known dimensions.
public export
record Pane (width : Nat) (height : Nat) where
  constructor MkPane
  id      : Nat
  content : String  -- captured terminal content
