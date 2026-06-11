import LeanProfiler

open LeanProfiler

def busy (n : Nat) : IO Nat := do
  let mut acc := 0
  for i in [0:n] do
    acc := acc + i
  pure acc

def runDemo : IO Unit := do
  clear
  withStep 0 do
    let _ ← recordSpanWith "load.batch"
      { phase := some "input", backend := some "lean", device := some "cpu" } do
        busy 25_000
    withModule "demo.mlp" do
      let _ ← recordSpanWith "linear"
        { phase := some "forward",
          backend := some "lean",
          dtype := some "float64",
          device := some "cpu",
          inputShapes := #["[32,128]", "[128,64]"],
          outputShape := some "[32,64]" } do
          busy 50_000
      let _ ← recordSpanWith "relu"
        { phase := some "forward",
          backend := some "lean",
          dtype := some "float64",
          device := some "cpu",
          inputShapes := #["[32,64]"],
          outputShape := some "[32,64]" } do
          busy 15_000
  finish .all "build/leanprofiler-trace.json"

def main : IO Unit := do
  runDemo
