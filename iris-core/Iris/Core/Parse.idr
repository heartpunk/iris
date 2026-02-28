module Iris.Core.Parse

||| Parse a decimal string to a natural number.
||| Returns Nothing on empty input or non-digit characters.
public export
parseNat : String -> Maybe Nat
parseNat s =
  case unpack s of
    [] => Nothing
    chars => foldl step (Just 0) chars
  where
    step : Maybe Nat -> Char -> Maybe Nat
    step Nothing _ = Nothing
    step (Just acc) ch =
      let d = the Int (ord ch - ord '0')
       in if d >= 0 && d < 10
            then Just (acc * 10 + cast d)
            else Nothing

||| Escape a list of characters for use inside single quotes in a shell command.
||| Single quotes are replaced with the sequence '\'' (end quote, escaped quote, start quote).
public export
escapeSingleQuoted : List Char -> String
escapeSingleQuoted [] = ""
escapeSingleQuoted ('\'' :: rest) = "'\\''" ++ escapeSingleQuoted rest
escapeSingleQuoted (ch :: rest) = strCons ch "" ++ escapeSingleQuoted rest

||| Wrap a string in single quotes, escaping any embedded single quotes.
public export
quoteArg : String -> String
quoteArg arg = "'" ++ escapeSingleQuoted (unpack arg) ++ "'"
