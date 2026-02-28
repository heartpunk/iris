module Iris.Native.Command

import Data.String

||| Commands that can be sent via the control pipe.
public export
data Command
  = SplitH
  | SplitV
  | SelectPane Nat
  | SelectWindow String
  | ListPanes
  | Quit

||| Parse a command string from the control pipe.
export
parseCommand : String -> Either String Command
parseCommand input =
  let trimmed = trim input
      parts = words trimmed
  in case parts of
    ["split-h"]       => Right SplitH
    ["split-v"]       => Right SplitV
    ["pane", n]       => case parsePositive n of
                           Just pn => Right (SelectPane pn)
                           Nothing => Left ("invalid pane number: " ++ n)
    ["window", name]  => Right (SelectWindow name)
    ["list"]          => Right ListPanes
    ["quit"]          => Right Quit
    _                 => Left ("unknown command: " ++ trimmed)

||| Show a command for debugging.
export
showCommand : Command -> String
showCommand SplitH = "split-h"
showCommand SplitV = "split-v"
showCommand (SelectPane n) = "pane " ++ show n
showCommand (SelectWindow n) = "window " ++ n
showCommand ListPanes = "list"
showCommand Quit = "quit"
