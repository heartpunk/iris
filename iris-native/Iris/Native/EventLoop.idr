module Iris.Native.EventLoop

import Data.Buffer
import Data.IORef
import Data.List
import Data.String
import Iris.Native.Command
import Iris.Native.FFI.Poll
import Iris.Native.FFI.Pty
import Iris.Native.FFI.Terminal
import Iris.Native.Render
import Iris.Native.State
import System.File.ReadWrite

||| Read buffer size for PTY reads.
readBufSize : Int
readBufSize = 4096

||| Find a pane by ID in the pane list.
findPane : Nat -> List PaneState -> Maybe PaneState
findPane pid [] = Nothing
findPane pid (p :: ps) = if p.paneId == pid then Just p else findPane pid ps

||| Update a pane in the list by ID.
updatePane : Nat -> (PaneState -> PaneState) -> List PaneState -> List PaneState
updatePane pid f [] = []
updatePane pid f (p :: ps) =
  if p.paneId == pid
    then f p :: ps
    else p :: updatePane pid f ps

||| Mark all panes as not dirty.
clearDirty : List PaneState -> List PaneState
clearDirty = map (\p => { dirty := False } p)

||| Append output to a pane's buffer, splitting on newlines.
appendOutput : String -> PaneState -> PaneState
appendOutput str p =
  let newLines = lines str
  in { buffer := p.buffer ++ newLines, dirty := True } p

||| Handle a command from the control pipe.
export
handleCommand : IORef MuxState -> Command -> IO ()
handleCommand stRef Quit = modifyIORef stRef (\st => { running := False } st)
handleCommand stRef ListPanes = do
  st <- readIORef stRef
  let showPane : PaneState -> String
      showPane p = "  pane " ++ show (the Nat p.paneId)
                   ++ (if p.paneId == st.activePaneId then " (active)" else "")
                   ++ (if p.closed then " (closed)" else "")
                   ++ "\n"
  putStr (concat (map showPane st.panes))
handleCommand stRef (SelectPane n) = do
  st <- readIORef stRef
  case findPane n st.panes of
    Nothing => putStr ("pane " ++ show (the Nat n) ++ " not found\n")
    Just _  => modifyIORef stRef (\s => { activePaneId := n } s)
handleCommand stRef (SelectWindow _) = pure () -- TODO: multi-window support
handleCommand stRef SplitH = pure () -- TODO: split implementation
handleCommand stRef SplitV = pure () -- TODO: split implementation

||| Read from an fd into a newly allocated buffer. Returns the string read, or Nothing.
readFdToString : Int -> IO (Maybe String)
readFdToString fd = do
  Just buf <- newBuffer readBufSize
    | Nothing => pure Nothing
  n <- ptyRead fd buf readBufSize
  if n <= 0
    then pure Nothing
    else do
      str <- getString buf 0 n
      pure (Just str)

||| Write a string to an fd via buffer.
writeStringToFd : Int -> String -> IO ()
writeStringToFd fd str = do
  let bytes = the (List Char) (unpack str)
  let len = cast {to=Int} (length str)
  Just buf <- newBuffer len
    | Nothing => pure ()
  setString buf 0 str
  _ <- ptyWrite fd buf len
  pure ()

||| Set up the poll set: stdin (fd 0) + all PTY master fds + control pipe.
setupPoll : MuxState -> IO (Int, List (Nat, Int), Int)
setupPoll st = do
  pollClear
  stdinIdx <- pollAdd 0
  paneIdxs <- traverse (\p => do idx <- pollAdd p.ptyFd
                                 pure (p.paneId, idx))
                       (filter (not . (.closed)) st.panes)
  ctlIdx <- if st.ctlPipeFd >= 0
              then pollAdd st.ctlPipeFd
              else pure (-1)
  pure (stdinIdx, paneIdxs, ctlIdx)

||| Single iteration of the event loop.
export
loopOnce : IORef MuxState -> IO ()
loopOnce stRef = do
  st <- readIORef stRef
  (stdinIdx, paneIdxs, ctlIdx) <- setupPoll st

  nReady <- pollWait (-1)
  when (nReady > 0) $ do
    -- Check stdin: forward to active pane's PTY
    stdinReady <- pollReadable stdinIdx
    when stdinReady $ do
      st' <- readIORef stRef
      case findPane st'.activePaneId st'.panes of
        Nothing => pure ()
        Just activePane => do
          mStr <- readFdToString 0
          case mStr of
            Nothing => pure ()
            Just str => writeStringToFd activePane.ptyFd str

    -- Check each PTY fd: read output, append to pane buffer
    traverse_ (\(pid, idx) => do
      readable <- pollReadable idx
      errored <- pollError idx
      when errored $
        modifyIORef stRef (\s => { panes := updatePane pid (\p => { closed := True } p) s.panes } s)
      when (readable && not errored) $ do
        s <- readIORef stRef
        case findPane pid s.panes of
          Nothing => pure ()
          Just pane => do
            mStr <- readFdToString pane.ptyFd
            case mStr of
              Nothing =>
                modifyIORef stRef (\s2 => { panes := updatePane pid (\p => { closed := True } p) s2.panes } s2)
              Just str =>
                modifyIORef stRef (\s2 => { panes := updatePane pid (appendOutput str) s2.panes } s2)
      ) paneIdxs

    -- Check control pipe
    when (ctlIdx >= 0) $ do
      ctlReady <- pollReadable ctlIdx
      when ctlReady $ do
        s <- readIORef stRef
        mStr <- readFdToString s.ctlPipeFd
        case mStr of
          Nothing => pure ()
          Just str =>
            case parseCommand str of
              Left _ => pure ()
              Right cmd => handleCommand stRef cmd

    -- Render dirty panes
    st'' <- readIORef stRef
    let output = renderDirtyPanes st''.panes
    when (output /= "") $ putStr output
    modifyIORef stRef (\s => { panes := clearDirty s.panes } s)

||| Main event loop: runs until state.running is False.
export
eventLoop : IORef MuxState -> IO ()
eventLoop stRef = do
  st <- readIORef stRef
  when st.running $ do
    loopOnce stRef
    eventLoop stRef
