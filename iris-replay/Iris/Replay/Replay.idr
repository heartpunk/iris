module Iris.Replay.Replay

import Iris.Core.Frame
import Iris.Replay.Ttyrec.Parse

byteToChar : Bits8 -> Char
byteToChar b = chr (cast (the Integer (cast b)))

payloadText : Frame -> String
payloadText frame = pack (map byteToChar (payload frame))

public export
replayUntimed : List Frame -> IO ()
replayUntimed [] = pure ()
replayUntimed (frame :: rest) = do
  putStr (payloadText frame)
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
