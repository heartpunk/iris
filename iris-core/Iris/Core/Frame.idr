module Iris.Core.Frame

||| A single ttyrec frame.
||| This stays intentionally untyped/simple so all packages can share it.
public export
record Frame where
  constructor MkFrame
  sec     : Nat
  usec    : Nat
  payload : String
