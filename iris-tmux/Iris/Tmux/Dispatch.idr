module Iris.Tmux.Dispatch

import Data.String
import System.File.Process
import System.File.ReadWrite

public export
data CaptureDepth = VisibleOnly | Lines Int | FullHistory

escapeSingleQuoted : List Char -> String
escapeSingleQuoted [] = ""
escapeSingleQuoted ('\'' :: rest) = "'\\''" ++ escapeSingleQuoted rest
escapeSingleQuoted (ch :: rest) = strCons ch "" ++ escapeSingleQuoted rest

quoteArg : String -> String
quoteArg arg = "'" ++ escapeSingleQuoted (unpack arg) ++ "'"

export
runTmux : List String -> IO (Either String String)
runTmux args = do
  let command = unwords (map quoteArg ("tmux" :: args))
  opened <- popen command Read
  case opened of
    Left err => pure (Left ("failed to start tmux: " ++ show err))
    Right process => do
      output <- fRead process
      exitCode <- pclose process
      case output of
        Left err => pure (Left ("failed to read tmux output: " ++ show err))
        Right stdout =>
          if exitCode == 0
            then pure (Right stdout)
            else pure (Left ("tmux exited with code " ++ show exitCode ++ ": " ++ stdout))

public export
tmuxNewSession : (name : String) -> IO (Either String ())
tmuxNewSession name = do
  result <- runTmux ["new-session", "-d", "-s", name]
  case result of
    Left err => pure (Left err)
    Right _ => pure (Right ())

public export
tmuxNewWindow : (session : String) -> (name : String) -> IO (Either String ())
tmuxNewWindow session name = do
  result <- runTmux ["new-window", "-t", session, "-n", name]
  case result of
    Left err => pure (Left err)
    Right _ => pure (Right ())

dropLeadingWhitespace : List Char -> List Char
dropLeadingWhitespace [] = []
dropLeadingWhitespace (ch :: rest) =
  if ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t'
    then dropLeadingWhitespace rest
    else ch :: rest

trimTrailingWhitespace : String -> String
trimTrailingWhitespace value =
  pack (reverse (dropLeadingWhitespace (reverse (unpack value))))

public export
tmuxSplitWindow : (target : String) -> IO (Either String String)
tmuxSplitWindow target = do
  result <- runTmux ["split-window", "-t", target, "-P", "-F", "#{pane_id}"]
  case result of
    Left err => pure (Left err)
    Right paneId => pure (Right (trimTrailingWhitespace paneId))

captureDepthArgs : CaptureDepth -> List String
captureDepthArgs VisibleOnly = []
captureDepthArgs (Lines n) = ["-S", "-" ++ show n]
captureDepthArgs FullHistory = ["-S", "-"]

public export
tmuxCapturePane : (target : String) -> (depth : CaptureDepth) -> IO (Either String String)
tmuxCapturePane target depth =
  runTmux (["capture-pane", "-t", target, "-p"] ++ captureDepthArgs depth)

public export
tmuxSendKeys : (target : String) -> (keys : String) -> IO (Either String ())
tmuxSendKeys target keys = do
  result <- runTmux ["send-keys", "-t", target, keys]
  case result of
    Left err => pure (Left err)
    Right _ => pure (Right ())

public export
tmuxListSessions : IO (Either String String)
tmuxListSessions = runTmux ["list-sessions"]

public export
tmuxAttachSession : (name : String) -> IO (Either String ())
tmuxAttachSession name = do
  result <- runTmux ["attach-session", "-t", name]
  pure (map (const ()) result)
