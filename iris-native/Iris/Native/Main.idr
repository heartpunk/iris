module Iris.Native.Main

import Data.IORef
import Data.String
import Iris.Native.Command
import Iris.Native.EventLoop
import Iris.Native.FFI.Fifo
import Iris.Native.FFI.Pty
import Iris.Native.FFI.Signal
import Iris.Native.FFI.Terminal
import Iris.Native.Render
import Iris.Native.State
import System
import System.File.ReadWrite

||| Create the control pipe and return its path.
mkCtlPipePath : IO String
mkCtlPipePath = do
  pid <- getPID
  pure ("/tmp/iris-" ++ show pid ++ ".ctl")

||| Server mode: single-pane passthrough (v0).
serveMode : IO ()
serveMode = do
  cols <- getTermCols
  rows <- getTermRows
  when (cols == 0 || rows == 0) $ do
    putStrLn "iris-native: cannot determine terminal size"
    exitWith (ExitFailure 1)

  -- Fork initial shell
  result <- forkPty cols rows
  case result of
    Left err => do
      putStrLn ("iris-native: " ++ err)
      exitWith (ExitFailure 1)
    Right fork => do
      -- Enter raw mode
      rc <- enterRawMode
      when (rc /= 0) $ do
        putStrLn "iris-native: failed to enter raw mode"
        exitWith (ExitFailure 1)

      -- Create control FIFO
      ctlPath <- mkCtlPipePath
      _ <- mkFifo ctlPath
      ctlFd <- openRdOnlyNonblock ctlPath

      -- Set IRIS_CTL env var for child processes
      True <- setEnv "IRIS_CTL" ctlPath True
        | False => do _ <- unlinkFile ctlPath
                      _ <- restoreTerminal
                      putStrLn "iris-native: failed to set IRIS_CTL"
                      exitWith (ExitFailure 1)

      let pane = MkPaneState
            { paneId   = 0
            , ptyFd    = fork.masterFd
            , childPid = fork.childPid
            , buffer   = []
            , dirty    = True
            , closed   = False
            , screenX  = 0
            , screenY  = 0
            , screenW  = cast cols
            , screenH  = cast rows
            }

      let initState = MkMuxState
            { panes        = [pane]
            , activePaneId = 0
            , nextPaneId   = 1
            , termCols     = cast cols
            , termRows     = cast rows
            , ctlPipePath  = ctlPath
            , ctlPipeFd    = ctlFd
            , running      = True
            }

      stRef <- newIORef initState

      -- Install signal handlers
      _ <- signalSetup

      -- Enter alternate screen buffer and clear
      putStr (enterAltScreen ++ clearScreen)

      -- Run event loop
      eventLoop stRef

      -- Cleanup: unlink FIFO, restore terminal
      _ <- unlinkFile ctlPath
      _ <- restoreTerminal
      putStr (exitAltScreen ++ showCursor)

||| Command mode: send a command to a running iris-native instance.
commandMode : List String -> IO ()
commandMode args = do
  ctlEnv <- getEnv "IRIS_CTL"
  case ctlEnv of
    Nothing => do
      putStrLn "iris-native: IRIS_CTL not set (not running inside iris-native?)"
      exitWith (ExitFailure 1)
    Just ctlPath => do
      let cmdStr = unwords args
      case parseCommand cmdStr of
        Left err => do
          putStrLn ("iris-native: " ++ err)
          exitWith (ExitFailure 1)
        Right _ => do
          -- Write command to control pipe
          result <- writeFile ctlPath (cmdStr ++ "\n")
          case result of
            Left err => do
              putStrLn ("iris-native: failed to write to control pipe: " ++ show err)
              exitWith (ExitFailure 1)
            Right () => pure ()

||| Entry point.
main : IO ()
main = do
  args <- getArgs
  case drop 1 args of  -- drop program name
    []         => serveMode
    ["serve"]  => serveMode
    cmdArgs    => commandMode cmdArgs
