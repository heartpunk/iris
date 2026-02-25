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

main : IO ()
main = do
  sessionName <- mkSessionName
  created <- tmuxNewSession sessionName
  case created of
    Left err => formatFailure ("tmuxNewSession failed: " ++ err)
    Right () => do
      windowCreated <- tmuxNewWindow sessionName "iris-window"
      killed <- runTmux ["kill-session", "-t", sessionName]
      case (windowCreated, killed) of
        (Right _, Right _) => putStrLn "iris-tmux-tests: ok"
        (Left windowErr, Right _) =>
          formatFailure ("tmuxNewWindow failed: " ++ windowErr)
        (Right _, Left killErr) =>
          formatFailure ("kill-session cleanup failed: " ++ killErr)
        (Left windowErr, Left killErr) =>
          formatFailure
            ("tmuxNewWindow failed: " ++ windowErr ++ "; cleanup failed: " ++ killErr)
