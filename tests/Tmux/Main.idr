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
      sentEcho <- tmuxSendKeys sessionName "echo hello"
      sentEnter <- tmuxSendKeys sessionName "Enter"
      waited <- runTmux ["run-shell", "sleep 0.1"]
      captured <- tmuxCapturePane sessionName FullHistory
      killed <- runTmux ["kill-session", "-t", sessionName]
      let captureValidated : Either String ()
          captureValidated =
            case sentEcho of
              Left err => Left ("tmuxSendKeys (echo hello) failed: " ++ err)
              Right _ =>
                case sentEnter of
                  Left err => Left ("tmuxSendKeys (Enter) failed: " ++ err)
                  Right _ =>
                    case waited of
                      Left err => Left ("wait step failed: " ++ err)
                      Right _ =>
                        case captured of
                          Left err => Left ("tmuxCapturePane failed: " ++ err)
                          Right output =>
                            if isInfixOf "hello" output
                              then Right ()
                              else Left "capture output missing \"hello\""
      case (captureValidated, killed) of
        (Right (), Right _) => putStrLn "iris-tmux-tests: ok"
        (Left captureErr, Right _) =>
          formatFailure captureErr
        (Right _, Left killErr) =>
          formatFailure ("kill-session cleanup failed: " ++ killErr)
        (Left captureErr, Left killErr) =>
          formatFailure
            (captureErr ++ "; cleanup failed: " ++ killErr)
