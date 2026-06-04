import LeanProfiler
import test.Model

def main : IO Unit := do
  withProfile "run" do
    IO.println "=== test run ==="
    train 3
  IO.println ""
  IO.println "=== summary ==="
  printSummary
