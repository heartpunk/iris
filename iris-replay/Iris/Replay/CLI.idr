module Iris.Replay.CLI

import Iris.Core.Frame
import Iris.Replay.Replay
import Iris.Replay.Search
import Iris.Replay.Ttyrec.Parse
import System

usage : String
usage =
  "iris-replay commands:\n" ++
  "  replay <path>          Replay a ttyrec to stdout\n" ++
  "  search <path> <query>  Search frame payload content\n" ++
  "  info <path>            Print basic frame stats"

normalizeArgs : List String -> List String
normalizeArgs [] = []
normalizeArgs all@(arg0 :: rest) =
  if arg0 == "replay" || arg0 == "search" || arg0 == "info"
    then all
    else rest

formatParseError : ParseError -> String
formatParseError err =
  "parse error at byte " ++ show (offset err) ++ ": " ++ message err

exitWithMessage : String -> IO ()
exitWithMessage msg = do
  putStrLn msg
  exitWith (ExitFailure 1)

runReplay : String -> IO ()
runReplay path = do
  result <- replayFile path
  case result of
    Left err => exitWithMessage (formatParseError err)
    Right () => pure ()

runSearch : String -> String -> IO ()
runSearch path query = do
  parsed <- parseFile path
  case parsed of
    Left err => exitWithMessage (formatParseError err)
    Right frames => do
      let matches = searchFrames query frames
      putStrLn ("matches: " ++ show (length matches))

runInfo : String -> IO ()
runInfo path = do
  parsed <- parseFile path
  case parsed of
    Left err => exitWithMessage (formatParseError err)
    Right frames => do
      putStrLn ("frames: " ++ show (length frames))

public export
main : IO ()
main = do
  rawArgs <- getArgs
  let args = normalizeArgs rawArgs
  case args of
    ["replay", path] => runReplay path
    ["search", path, query] => runSearch path query
    ["info", path] => runInfo path
    _ => exitWithMessage usage
