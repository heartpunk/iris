module Iris.Compress.UUID

||| Check if a character is a lowercase hex digit (0-9, a-f).
public export
isHexChar : Char -> Bool
isHexChar c = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')

||| Check if a list of characters are all lowercase hex digits.
allHex : List Char -> Bool
allHex [] = True
allHex (c :: cs) = isHexChar c && allHex cs

||| Check a segment of exactly n hex characters.
hexSegment : Nat -> List Char -> Maybe (List Char)
hexSegment Z rest = Just rest
hexSegment (S k) [] = Nothing
hexSegment (S k) (c :: cs) =
  if isHexChar c then hexSegment k cs else Nothing

||| Consume a literal hyphen.
expectHyphen : List Char -> Maybe (List Char)
expectHyphen ('-' :: cs) = Just cs
expectHyphen _ = Nothing

||| Check if a string matches the UUID format:
||| 8-4-4-4-12 lowercase hex digits separated by hyphens.
public export
isUUIDFormat : String -> Bool
isUUIDFormat s =
  case hexSegment 8 (unpack s) of
    Nothing => False
    Just r1 => case expectHyphen r1 of
      Nothing => False
      Just r2 => case hexSegment 4 r2 of
        Nothing => False
        Just r3 => case expectHyphen r3 of
          Nothing => False
          Just r4 => case hexSegment 4 r4 of
            Nothing => False
            Just r5 => case expectHyphen r5 of
              Nothing => False
              Just r6 => case hexSegment 4 r6 of
                Nothing => False
                Just r7 => case expectHyphen r7 of
                  Nothing => False
                  Just r8 => case hexSegment 12 r8 of
                    Nothing => False
                    Just [] => True
                    Just _  => False

||| A validated UUID string.
public export
record ValidUUID where
  constructor MkValidUUID
  uuid : String

public export
Eq ValidUUID where
  a == b = uuid a == uuid b

public export
Show ValidUUID where
  show v = uuid v

||| Validate a string as a UUID, returning a ValidUUID on success.
public export
validateUUID : String -> Maybe ValidUUID
validateUUID s = if isUUIDFormat s then Just (MkValidUUID s) else Nothing
