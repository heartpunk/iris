module Tmux.Main

import Iris.Tmux.Dispatch
import System
import System.Clock

mkSessionName : IO String
mkSessionName = do
  now <- clockTime UTC
  pure ("iris-test-" ++ show (seconds now) ++ "-" ++ show (nanoseconds now))

formatFailure : String -> IO ()
formatFailure msg = do
  putStrLn ("iris-tmux-tests: FAIL: " ++ msg)
  exitWith (ExitFailure 1)

isValidPaneId : String -> Bool
isValidPaneId paneId =
  case unpack paneId of
    '%' :: _ => True
    _ => False

main : IO ()
main = do
  sessionName <- mkSessionName
  created <- tmuxNewSession sessionName
  case created of
    Left err => formatFailure ("tmuxNewSession failed: " ++ err)
    Right () => do
      splitResult <- tmuxSplitWindow sessionName
      killed <- runTmux ["kill-session", "-t", sessionName]
      let splitValidated : Either String ()
          splitValidated =
            case splitResult of
              Left err => Left ("tmuxSplitWindow failed: " ++ err)
              Right paneId =>
                if isValidPaneId paneId
                  then Right ()
                  else Left ("tmuxSplitWindow returned invalid pane id: " ++ show paneId)
      case (splitValidated, killed) of
        (Right (), Right _) => putStrLn "iris-tmux-tests: ok"
        (Left splitErr, Right _) =>
          formatFailure splitErr
        (Right _, Left killErr) =>
          formatFailure ("kill-session cleanup failed: " ++ killErr)
        (Left splitErr, Left killErr) =>
          formatFailure
            (splitErr ++ "; cleanup failed: " ++ killErr)
