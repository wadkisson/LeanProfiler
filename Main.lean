import LeanProfiler

set_option profiler.rewrite true

@[profile]
def work : IO Nat := do
  IO.sleep 5
  pure 42

def main : IO Unit := do
  withProfile "main" do
    let n ← work
    IO.println s!"result={n}"
  printSummary
  exportFlameGraph "build/trace.json"
