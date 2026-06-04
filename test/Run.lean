import LeanProfiler
import test.Model

def main : IO Unit := profileRun do
  IO.println "=== test run ==="
  train 3
  IO.println ""
  IO.println "=== summary ==="
  printSummary
