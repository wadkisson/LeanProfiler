import LeanProfiler

def helper : IO Nat := do
  IO.sleep 50
  pure 42

def other : IO Nat := do
  IO.sleep 30
  pure 7

/-- Mimics `nn.withModel … fun _ => do` without pulling in TorchLean. -/
def withModelSim (k : Nat → IO Nat) : IO Nat :=
  k 0

@[profile]
def trainSim : IO Nat := do
  withModelSim fun _ => do
    let a ← helper
    let b ← other
    pure (a + b)

def main : IO Unit := do
  let n ← trainSim
  IO.println s!"result={n}"
