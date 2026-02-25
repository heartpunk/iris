module Iris.Replay.Replay

import Iris.Core.Frame
import Iris.Replay.Ttyrec.Parse

public export
replayUntimed : List Frame -> IO ()
replayUntimed [] = pure ()
replayUntimed (frame :: rest) = do
  putStr (payload frame)
  replayUntimed rest

public export
replayFile : String -> IO (Either ParseError ())
replayFile path = do
  parsed <- parseFile path
  case parsed of
    Left err => pure (Left err)
    Right frames => do
      replayUntimed frames
      pure (Right ())
