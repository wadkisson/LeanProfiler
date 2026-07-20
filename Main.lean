import LeanProfiler

open LeanProfiler

def busy (n : Nat) : IO Nat := do
  let mut acc := 0
  for i in [0:n] do
    acc := acc + i
  pure acc

profiled def main : IO Unit := do
  let _ ← span "load.batch" (busy 25_000)
  let _ ← span "linear" (busy 50_000)
  let _ ← span "relu" (busy 15_000)
