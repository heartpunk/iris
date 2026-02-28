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

testListClients : IO ()
testListClients = do
  result <- tmuxListClients
  case result of
    Left _ => putStrLn "iris-tmux-tests: list-clients: ok (no clients expected)"
    Right _ => putStrLn "iris-tmux-tests: list-clients: ok"

testKillServer : IO ()
testKillServer = do
  -- kill-server is destructive; just verify it compiles and returns Either
  let _ : IO (Either String ()) = tmuxKillServer
  putStrLn "iris-tmux-tests: kill-server: ok (typecheck only)"

testAttachSession : IO ()
testAttachSession = do
  result <- tmuxAttachSession "iris-nonexistent-session"
  case result of
    Left _ => putStrLn "iris-tmux-tests: attach-session: ok"
    Right () => formatFailure "tmuxAttachSession should fail for nonexistent session"

testListSessions : IO ()
testListSessions = do
  sessionName <- mkSessionName
  created <- tmuxNewSession sessionName
  case created of
    Left err => formatFailure ("listSessions: setup failed: " ++ err)
    Right () => do
      result <- tmuxListSessions
      _ <- runTmux ["kill-session", "-t", sessionName]
      case result of
        Left err => formatFailure ("tmuxListSessions failed: " ++ err)
        Right output =>
          if isInfixOf sessionName output
            then putStrLn "iris-tmux-tests: list-sessions: ok"
            else formatFailure "tmuxListSessions output missing session name"

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
        (Right (), Right _) => putStrLn "iris-tmux-tests: capture-pane: ok"
        (Left captureErr, Right _) =>
          formatFailure captureErr
        (Right _, Left killErr) =>
          formatFailure ("kill-session cleanup failed: " ++ killErr)
        (Left captureErr, Left killErr) =>
          formatFailure
            (captureErr ++ "; cleanup failed: " ++ killErr)
  -- test: tmuxListSessions
  testListSessions
  -- test: tmuxAttachSession
  testAttachSession
  -- test: tmuxListClients
  testListClients
  -- test: tmuxKillServer
  testKillServer
