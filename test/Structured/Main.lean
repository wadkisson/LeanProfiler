import LeanProfiler

open LeanProfiler

def busy (n : Nat) : IO Nat := do
  let mut acc := 0
  for i in [0:n] do
    acc := acc + i
  pure acc

def fakeForward : IO Unit := do
  let matmulMetadata : Metadata :=
    { phase := some "forward",
      backend := some "cuda",
      dtype := some "float32",
      device := some "cuda:0",
      moduleName := some "gpt2.block0.attn.q_proj",
      graphNode := some "node_17",
      inputShapes := #["[2,64,32]", "[32,32]"],
      outputShape := some "[2,64,32]",
      allocBytes := some 16384 }
  let _ ← recordSpanWith "matmul" matmulMetadata do
    busy 10000
  let reluMetadata : Metadata :=
    { phase := some "forward",
      backend := some "cpu",
      dtype := some "float32",
      inputShapes := #["[2,64,32]"],
      outputShape := some "[2,64,32]" }
  let _ ← recordSpanWith "relu" reluMetadata do
    busy 5000
  pure ()

def main : IO Unit := do
  clear
  fakeForward
  finish .all "build/leanprofiler-structured-trace.json"
