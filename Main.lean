import LeanProfiler

def loadBatch (batchIdx : Nat) : IO (List Float) := do
  IO.sleep 10
  pure (List.replicate 32 (Float.ofNat batchIdx * 0.1))

def linearLayer (input : List Float) : IO (List Float) := do
  IO.sleep 5
  pure (input.map (· * 2.0))

def reluActivation (input : List Float) : IO (List Float) := do
  IO.sleep 2
  pure (input.map (fun x => if x > 0.0 then x else 0.0))

def forwardPass (input : List Float) : IO (List Float) := do
  let h1 ← linearLayer input
  let a1 ← reluActivation h1
  let h2 ← linearLayer a1
  let a2 ← reluActivation h2
  pure a2

def computeLoss (output : List Float) : IO Float := do
  IO.sleep 3
  let sum := output.foldl (· + ·) 0.0
  pure (sum / Float.ofNat output.length)

def backwardPass (loss : Float) : IO Unit := do
  IO.sleep 8
  pure ()

def optimizerStep : IO Unit := do
  IO.sleep 4
  pure ()

@[profile]
def trainStep (batchIdx : Nat) : IO Float := do
  let batch  ← loadBatch batchIdx
  let output ← forwardPass batch
  let loss   ← computeLoss output
  backwardPass loss
  optimizerStep
  pure loss

def trainModel (epochs : Nat) (batchesPerEpoch : Nat) : IO Unit := do
  for epoch in List.range epochs do
    let mut epochLoss := 0.0
    for batch in List.range batchesPerEpoch do
      let loss ← trainStep (epoch * batchesPerEpoch + batch)
      epochLoss := epochLoss + loss
    let avg := epochLoss / Float.ofNat batchesPerEpoch
    IO.println s!"Epoch {epoch + 1}: avg loss = {avg}"

def main : IO Unit := profileRun do
  IO.println "=== Training ==="
  trainModel 2 3
  IO.println ""
  IO.println "=== Summary ==="
  printSummary
