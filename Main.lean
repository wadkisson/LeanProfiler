import LeanProfiler

def work : IO Nat := do
  IO.sleep 1
  pure 42

def main : IO Unit := do
  let n ← work
  IO.println s!"result={n}"
