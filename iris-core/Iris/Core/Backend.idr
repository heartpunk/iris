module Iris.Core.Backend

import Iris.Core.Session
import Iris.Core.Window
import Iris.Core.Pane
import Iris.Core.Layout
import Iris.Core.Error

||| Abstract backend interface.
||| iris-tmux and iris-native both implement this.
||| Swapping backends doesn't change iris-core or any code above it.
public export
interface Backend b where
  newSession  : b -> String -> IO (Either IrisError Session)
  newWindow   : b -> Session -> String -> (w : Nat) -> (h : Nat)
             -> IO (Either IrisError (Window w h))
  splitPane   : b -> Session -> String -> Direction
             -> IO (Either IrisError Session)
  capturePane : b -> Nat -> IO (Either IrisError String)
  sendKeys    : b -> Nat -> String -> IO (Either IrisError ())
  listSessions : b -> IO (Either IrisError (List Session))
