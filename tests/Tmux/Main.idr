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
      hasSession <- runTmux ["has-session", "-t", sessionName]
      killed <- runTmux ["kill-session", "-t", sessionName]
      case (hasSession, killed) of
        (Right _, Right _) => putStrLn "iris-tmux-tests: ok"
        (Left verifyErr, Right _) =>
          formatFailure ("has-session failed: " ++ verifyErr)
        (Right _, Left killErr) =>
          formatFailure ("kill-session cleanup failed: " ++ killErr)
        (Left verifyErr, Left killErr) =>
          formatFailure
            ("has-session failed: " ++ verifyErr ++ "; cleanup failed: " ++ killErr)
