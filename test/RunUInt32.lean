import LeanProfiler

set_option profiler.rewrite true

@[profile]
def work : IO Nat := do
  IO.sleep 2
  pure 42

def main : IO UInt32 := do
  withProfile "run" do
    let n ← work
    IO.println s!"result={n}"
    printSummary
  pure 0
