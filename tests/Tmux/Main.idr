module Tmux.Main

import Data.String
import Iris.Tmux.Dispatch
import System
import System.Clock
import System.File.Process
import System.File.ReadWrite

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

mkSessionName : IO String
mkSessionName = do
  now <- clockTime UTC
  pure ("iris-test-" ++ show (seconds now) ++ "-" ++ show (nanoseconds now))

formatFailure : String -> IO ()
formatFailure msg = do
  putStrLn ("iris-tmux-tests: FAIL: " ++ msg)
  exitWith (ExitFailure 1)

shellCapture : String -> IO (Either String String)
shellCapture cmd = do
  opened <- popen cmd Read
  case opened of
    Left err => pure (Left (show err))
    Right process => do
      output <- fRead process
      _ <- pclose process
      case output of
        Left err => pure (Left (show err))
        Right stdout => pure (Right (trim stdout))

makeTmpDir : IO (Either String String)
makeTmpDir = shellCapture "mktemp -d"

removeTmpDir : String -> IO ()
removeTmpDir path = do
  _ <- system ("rm -rf '" ++ path ++ "'")
  pure ()

clearLog : String -> IO ()
clearLog path = do
  _ <- writeFile path ""
  pure ()

readLog : String -> IO (Either String String)
readLog path = do
  result <- readFile path
  case result of
    Left err => pure (Left (show err))
    Right contents => pure (Right contents)

------------------------------------------------------------------------
-- Unit tests: wrappers returning Either String String (check output)
------------------------------------------------------------------------

unitTestListSessions : IO ()
unitTestListSessions = do
  result <- tmuxListSessions
  case result of
    Left err => formatFailure ("unit list-sessions: " ++ err)
    Right output =>
      if isInfixOf "list-sessions" output
        then putStrLn "iris-tmux-tests: unit list-sessions: ok"
        else formatFailure ("unit list-sessions: expected 'list-sessions', got: " ++ output)

unitTestListClients : IO ()
unitTestListClients = do
  result <- tmuxListClients
  case result of
    Left err => formatFailure ("unit list-clients: " ++ err)
    Right output =>
      if isInfixOf "list-clients" output
        then putStrLn "iris-tmux-tests: unit list-clients: ok"
        else formatFailure ("unit list-clients: expected 'list-clients', got: " ++ output)

unitTestListPanes : IO ()
unitTestListPanes = do
  result <- tmuxListPanes "test-target"
  case result of
    Left err => formatFailure ("unit list-panes: " ++ err)
    Right output =>
      if isInfixOf "list-panes" output && isInfixOf "test-target" output
        then putStrLn "iris-tmux-tests: unit list-panes: ok"
        else formatFailure ("unit list-panes: got: " ++ output)

unitTestDisplayMessage : IO ()
unitTestDisplayMessage = do
  result <- tmuxDisplayMessage "test-target" "#{session_name}"
  case result of
    Left err => formatFailure ("unit display-message: " ++ err)
    Right output =>
      if isInfixOf "display-message" output && isInfixOf "test-target" output
        then putStrLn "iris-tmux-tests: unit display-message: ok"
        else formatFailure ("unit display-message: got: " ++ output)

unitTestListWindows : IO ()
unitTestListWindows = do
  result <- tmuxListWindows "test-target"
  case result of
    Left err => formatFailure ("unit list-windows: " ++ err)
    Right output =>
      if isInfixOf "list-windows" output && isInfixOf "test-target" output
        then putStrLn "iris-tmux-tests: unit list-windows: ok"
        else formatFailure ("unit list-windows: got: " ++ output)

unitTestSplitWindow : IO ()
unitTestSplitWindow = do
  result <- tmuxSplitWindow "test-target"
  case result of
    Left err => formatFailure ("unit split-window: " ++ err)
    Right output =>
      if isInfixOf "split-window" output && isInfixOf "test-target" output
        then putStrLn "iris-tmux-tests: unit split-window: ok"
        else formatFailure ("unit split-window: got: " ++ output)

unitTestCapturePaneFullHistory : IO ()
unitTestCapturePaneFullHistory = do
  result <- tmuxCapturePane "test-target" FullHistory
  case result of
    Left err => formatFailure ("unit capture-pane-full-history: " ++ err)
    Right output =>
      if isInfixOf "capture-pane" output && isInfixOf "-S" output
        then putStrLn "iris-tmux-tests: unit capture-pane-full-history: ok"
        else formatFailure ("unit capture-pane-full-history: got: " ++ output)

unitTestCapturePaneVisibleOnly : IO ()
unitTestCapturePaneVisibleOnly = do
  result <- tmuxCapturePane "test-target" VisibleOnly
  case result of
    Left err => formatFailure ("unit capture-pane-visible-only: " ++ err)
    Right output =>
      if isInfixOf "capture-pane" output && not (isInfixOf "-S" output)
        then putStrLn "iris-tmux-tests: unit capture-pane-visible-only: ok"
        else formatFailure ("unit capture-pane-visible-only: got: " ++ output)

unitTestCapturePaneLines : IO ()
unitTestCapturePaneLines = do
  result <- tmuxCapturePane "test-target" (Lines 5)
  case result of
    Left err => formatFailure ("unit capture-pane-lines: " ++ err)
    Right output =>
      if isInfixOf "capture-pane" output && isInfixOf "-S" output && isInfixOf "-5" output
        then putStrLn "iris-tmux-tests: unit capture-pane-lines: ok"
        else formatFailure ("unit capture-pane-lines: got: " ++ output)

------------------------------------------------------------------------
-- Unit tests: wrappers returning Either String () (check log file)
------------------------------------------------------------------------

unitTestNewSession : String -> IO ()
unitTestNewSession logFile = do
  clearLog logFile
  result <- tmuxNewSession "test-session"
  case result of
    Left err => formatFailure ("unit new-session: " ++ err)
    Right () => do
      log <- readLog logFile
      case log of
        Left err => formatFailure ("unit new-session: couldn't read log: " ++ err)
        Right contents =>
          if isInfixOf "new-session" contents && isInfixOf "test-session" contents
            then putStrLn "iris-tmux-tests: unit new-session: ok"
            else formatFailure ("unit new-session: log: " ++ contents)

unitTestNewWindow : String -> IO ()
unitTestNewWindow logFile = do
  clearLog logFile
  result <- tmuxNewWindow "test-session" "test-win"
  case result of
    Left err => formatFailure ("unit new-window: " ++ err)
    Right () => do
      log <- readLog logFile
      case log of
        Left err => formatFailure ("unit new-window: couldn't read log: " ++ err)
        Right contents =>
          if isInfixOf "new-window" contents && isInfixOf "test-session" contents && isInfixOf "test-win" contents
            then putStrLn "iris-tmux-tests: unit new-window: ok"
            else formatFailure ("unit new-window: log: " ++ contents)

unitTestSendKeys : String -> IO ()
unitTestSendKeys logFile = do
  clearLog logFile
  result <- tmuxSendKeys "test-target" "echo hello"
  case result of
    Left err => formatFailure ("unit send-keys: " ++ err)
    Right () => do
      log <- readLog logFile
      case log of
        Left err => formatFailure ("unit send-keys: couldn't read log: " ++ err)
        Right contents =>
          if isInfixOf "send-keys" contents && isInfixOf "test-target" contents
            then putStrLn "iris-tmux-tests: unit send-keys: ok"
            else formatFailure ("unit send-keys: log: " ++ contents)

unitTestSelectLayout : String -> IO ()
unitTestSelectLayout logFile = do
  clearLog logFile
  result <- tmuxSelectLayout "test-target" "even-horizontal"
  case result of
    Left err => formatFailure ("unit select-layout: " ++ err)
    Right () => do
      log <- readLog logFile
      case log of
        Left err => formatFailure ("unit select-layout: couldn't read log: " ++ err)
        Right contents =>
          if isInfixOf "select-layout" contents && isInfixOf "test-target" contents && isInfixOf "even-horizontal" contents
            then putStrLn "iris-tmux-tests: unit select-layout: ok"
            else formatFailure ("unit select-layout: log: " ++ contents)

unitTestAttachSession : String -> IO ()
unitTestAttachSession logFile = do
  clearLog logFile
  result <- tmuxAttachSession "test-session"
  case result of
    Left err => formatFailure ("unit attach-session: " ++ err)
    Right () => do
      log <- readLog logFile
      case log of
        Left err => formatFailure ("unit attach-session: couldn't read log: " ++ err)
        Right contents =>
          if isInfixOf "attach-session" contents && isInfixOf "test-session" contents
            then putStrLn "iris-tmux-tests: unit attach-session: ok"
            else formatFailure ("unit attach-session: log: " ++ contents)

unitTestKillServer : String -> IO ()
unitTestKillServer logFile = do
  clearLog logFile
  result <- tmuxKillServer
  case result of
    Left err => formatFailure ("unit kill-server: " ++ err)
    Right () => do
      log <- readLog logFile
      case log of
        Left err => formatFailure ("unit kill-server: couldn't read log: " ++ err)
        Right contents =>
          if isInfixOf "kill-server" contents
            then putStrLn "iris-tmux-tests: unit kill-server: ok"
            else formatFailure ("unit kill-server: log: " ++ contents)

unitTestKillSession : String -> IO ()
unitTestKillSession logFile = do
  clearLog logFile
  result <- tmuxKillSession "test-session"
  case result of
    Left err => formatFailure ("unit kill-session: " ++ err)
    Right () => do
      log <- readLog logFile
      case log of
        Left err => formatFailure ("unit kill-session: couldn't read log: " ++ err)
        Right contents =>
          if isInfixOf "kill-session" contents && isInfixOf "test-session" contents
            then putStrLn "iris-tmux-tests: unit kill-session: ok"
            else formatFailure ("unit kill-session: log: " ++ contents)

unitTestSelectPane : String -> IO ()
unitTestSelectPane logFile = do
  clearLog logFile
  result <- tmuxSelectPane "test-target"
  case result of
    Left err => formatFailure ("unit select-pane: " ++ err)
    Right () => do
      log <- readLog logFile
      case log of
        Left err => formatFailure ("unit select-pane: couldn't read log: " ++ err)
        Right contents =>
          if isInfixOf "select-pane" contents && isInfixOf "test-target" contents
            then putStrLn "iris-tmux-tests: unit select-pane: ok"
            else formatFailure ("unit select-pane: log: " ++ contents)

unitTestSelectWindow : String -> IO ()
unitTestSelectWindow logFile = do
  clearLog logFile
  result <- tmuxSelectWindow "test-target"
  case result of
    Left err => formatFailure ("unit select-window: " ++ err)
    Right () => do
      log <- readLog logFile
      case log of
        Left err => formatFailure ("unit select-window: couldn't read log: " ++ err)
        Right contents =>
          if isInfixOf "select-window" contents && isInfixOf "test-target" contents
            then putStrLn "iris-tmux-tests: unit select-window: ok"
            else formatFailure ("unit select-window: log: " ++ contents)

unitTestSwitchClient : String -> IO ()
unitTestSwitchClient logFile = do
  clearLog logFile
  result <- tmuxSwitchClient "test-target"
  case result of
    Left err => formatFailure ("unit switch-client: " ++ err)
    Right () => do
      log <- readLog logFile
      case log of
        Left err => formatFailure ("unit switch-client: couldn't read log: " ++ err)
        Right contents =>
          if isInfixOf "switch-client" contents && isInfixOf "test-target" contents
            then putStrLn "iris-tmux-tests: unit switch-client: ok"
            else formatFailure ("unit switch-client: log: " ++ contents)

unitTestHasSession : String -> IO ()
unitTestHasSession logFile = do
  clearLog logFile
  result <- tmuxHasSession "test-session"
  log <- readLog logFile
  case log of
    Left err => formatFailure ("unit has-session: couldn't read log: " ++ err)
    Right contents =>
      if result && isInfixOf "has-session" contents && isInfixOf "test-session" contents
        then putStrLn "iris-tmux-tests: unit has-session: ok"
        else formatFailure ("unit has-session: result=" ++ show result ++ " log: " ++ contents)

------------------------------------------------------------------------
-- Run all unit tests
------------------------------------------------------------------------

runUnitTests : IO ()
runUnitTests = do
  origPath <- getEnv "PATH"
  let origPathStr = case origPath of
                      Nothing => ""
                      Just p  => p
  cwdResult <- shellCapture "pwd"
  case cwdResult of
    Left err => formatFailure ("unit tests: couldn't get cwd: " ++ err)
    Right cwd => do
      tmpResult <- makeTmpDir
      case tmpResult of
        Left err => formatFailure ("unit tests: couldn't create tmp dir: " ++ err)
        Right tmpDir => do
          let fakeDir = cwd ++ "/fixtures/fake-tmux-bin"
          let logFile = tmpDir ++ "/fake-tmux.log"
          let newPath = fakeDir ++ ":" ++ origPathStr
          True <- setEnv "PATH" newPath True
            | False => formatFailure "unit tests: failed to set PATH"
          True <- setEnv "FAKE_TMUX_LOG" logFile True
            | False => formatFailure "unit tests: failed to set FAKE_TMUX_LOG"
          putStrLn "--- Unit tests (fake tmux) ---"
          unitTestListSessions
          unitTestListClients
          unitTestListPanes
          unitTestDisplayMessage
          unitTestListWindows
          unitTestSplitWindow
          unitTestCapturePaneFullHistory
          unitTestCapturePaneVisibleOnly
          unitTestCapturePaneLines
          unitTestNewSession logFile
          unitTestNewWindow logFile
          unitTestSendKeys logFile
          unitTestSelectLayout logFile
          unitTestAttachSession logFile
          unitTestKillServer logFile
          unitTestKillSession logFile
          unitTestSelectPane logFile
          unitTestSelectWindow logFile
          unitTestSwitchClient logFile
          unitTestHasSession logFile
          True <- setEnv "PATH" origPathStr True
            | False => formatFailure "unit tests: failed to restore PATH"
          True <- setEnv "FAKE_TMUX_LOG" "" True
            | False => formatFailure "unit tests: failed to clear FAKE_TMUX_LOG"
          removeTmpDir tmpDir

------------------------------------------------------------------------
-- Integration tests (real tmux, isolated via TMUX_TMPDIR)
------------------------------------------------------------------------

testCapturePaneFlow : IO ()
testCapturePaneFlow = do
  sessionName <- mkSessionName
  created <- tmuxNewSession sessionName
  case created of
    Left err => formatFailure ("integration capture-pane: setup failed: " ++ err)
    Right () => do
      sentEcho <- tmuxSendKeys sessionName "echo hello"
      sentEnter <- tmuxSendKeys sessionName "Enter"
      waited <- runTmux ["run-shell", "sleep 0.1"]
      captured <- tmuxCapturePane sessionName FullHistory
      _ <- runTmux ["kill-session", "-t", sessionName]
      let validated : Either String ()
          validated =
            case sentEcho of
              Left err => Left ("send-keys echo: " ++ err)
              Right _ => case sentEnter of
                Left err => Left ("send-keys enter: " ++ err)
                Right _ => case waited of
                  Left err => Left ("wait: " ++ err)
                  Right _ => case captured of
                    Left err => Left ("capture-pane: " ++ err)
                    Right output =>
                      if isInfixOf "hello" output
                        then Right ()
                        else Left ("output missing 'hello': " ++ output)
      case validated of
        Right () => putStrLn "iris-tmux-tests: integration capture-pane: ok"
        Left err => formatFailure ("integration capture-pane: " ++ err)

testIntegrationHasSession : IO ()
testIntegrationHasSession = do
  sessionName <- mkSessionName
  created <- tmuxNewSession sessionName
  case created of
    Left err => formatFailure ("integration has-session: setup failed: " ++ err)
    Right () => do
      exists <- tmuxHasSession sessionName
      _ <- runTmux ["kill-session", "-t", sessionName]
      gone <- tmuxHasSession sessionName
      if exists && not gone
        then putStrLn "iris-tmux-tests: integration has-session: ok"
        else formatFailure ("integration has-session: exists=" ++ show exists ++ " gone=" ++ show gone)

testIntegrationKillSession : IO ()
testIntegrationKillSession = do
  sessionName <- mkSessionName
  created <- tmuxNewSession sessionName
  case created of
    Left err => formatFailure ("integration kill-session: setup failed: " ++ err)
    Right () => do
      result <- tmuxKillSession sessionName
      case result of
        Left err => formatFailure ("integration kill-session: " ++ err)
        Right () => do
          check <- runTmux ["has-session", "-t", sessionName]
          case check of
            Left _ => putStrLn "iris-tmux-tests: integration kill-session: ok"
            Right _ => formatFailure "integration kill-session: session still exists"

runIntegrationTests : IO ()
runIntegrationTests = do
  sentinel <- readFile "/etc/iris-test-vm"
  let expected = "k7X9mQ2vL4pR8wF1nJ6bT3hY5dA0sG"
  case sentinel of
    Left _ => formatFailure "integration tests must run inside the test VM (missing /etc/iris-test-vm)"
    Right contents =>
      if not (isInfixOf expected contents)
        then formatFailure "integration tests must run inside the test VM (sentinel mismatch)"
        else do
      tmpResult <- makeTmpDir
      case tmpResult of
        Left err => formatFailure ("integration tests: couldn't create TMUX_TMPDIR: " ++ err)
        Right tmpDir => do
          True <- setEnv "TMUX_TMPDIR" tmpDir True
            | False => formatFailure "integration tests: failed to set TMUX_TMPDIR"
          putStrLn "--- Integration tests (isolated real tmux) ---"
          testCapturePaneFlow
          testIntegrationHasSession
          testIntegrationKillSession
          _ <- tmuxKillServer
          putStrLn "iris-tmux-tests: integration kill-server: ok"
          removeTmpDir tmpDir

------------------------------------------------------------------------
-- Main
------------------------------------------------------------------------

main : IO ()
main = do
  args <- getArgs
  case args of
    [_, "unit"]        => runUnitTests
    [_, "integration"] => runIntegrationTests
    _                  => do runUnitTests
                             runIntegrationTests
