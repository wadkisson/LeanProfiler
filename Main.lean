import LeanProfiler

@[profile]
def work : IO Nat := do
  IO.sleep 5
  pure 42

def main : IO Unit := do
  let n ← work
  IO.println s!"result={n}"
  profile
