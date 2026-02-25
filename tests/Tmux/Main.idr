module Tmux.Main

import Data.String
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
      let marker = "iris-capture-pane-hello"
      sent <- runTmux ["send-keys", "-t", sessionName, "echo " ++ marker, "Enter"]
      waited <- runTmux ["run-shell", "sleep 0.1"]
      captured <- tmuxCapturePane sessionName FullHistory
      killed <- runTmux ["kill-session", "-t", sessionName]
      let captureValidated : Either String ()
          captureValidated =
            case sent of
              Left err => Left ("send-keys failed: " ++ err)
              Right _ =>
                case waited of
                  Left err => Left ("wait step failed: " ++ err)
                  Right _ =>
                    case captured of
                      Left err => Left ("tmuxCapturePane failed: " ++ err)
                      Right output =>
                        if isInfixOf marker output
                          then Right ()
                          else Left ("capture output missing marker " ++ show marker)
      case (captureValidated, killed) of
        (Right (), Right _) => putStrLn "iris-tmux-tests: ok"
        (Left captureErr, Right _) =>
          formatFailure captureErr
        (Right _, Left killErr) =>
          formatFailure ("kill-session cleanup failed: " ++ killErr)
        (Left captureErr, Left killErr) =>
          formatFailure
            (captureErr ++ "; cleanup failed: " ++ killErr)
