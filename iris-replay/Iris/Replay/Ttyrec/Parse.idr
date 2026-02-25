module Iris.Replay.Ttyrec.Parse

import Iris.Core.Frame

public export
record ParseError where
  constructor MkParseError
  offset  : Nat
  message : String

public export
parseBytes : String -> Either ParseError (List Frame)
parseBytes _ = Left (MkParseError 0 "ttyrec parser not implemented yet")

public export
parseFile : String -> IO (Either ParseError (List Frame))
parseFile _ = pure (Left (MkParseError 0 "ttyrec file parser not implemented yet"))
