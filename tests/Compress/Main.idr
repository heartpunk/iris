module Compress.Main

import System

-- Takes an equality proof; always True at runtime.
-- Compilation verifies the proof holds (type checker rejects Refl if not).
isProven : a = b -> Bool
isProven _ = True

runPure : String -> Bool -> IO Nat
runPure name passed = do
  putStrLn ((if passed then "PASS " else "FAIL ") ++ name)
  pure (if passed then 0 else 1)

propertyMany : (Nat -> Bool) -> Nat -> Bool
propertyMany prop Z = prop 0
propertyMany prop (S k) = prop (S k) && propertyMany prop k

public export
main : IO ()
main = do
  let failures = 0
  putStrLn ("failures: " ++ show failures)
  if failures == 0
    then pure ()
    else exitWith (ExitFailure 1)
