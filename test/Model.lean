import LeanProfiler

def tensorScale (xs : List Float) (k : Float) : List Float :=
  xs.map (· * k)

@[profile]
def forward (input : List Float) : IO (List Float) := do
  IO.sleep 5
  pure (input.map (· * 2.0))

@[profile]
def trainStep : IO Float := do
  let scaled := tensorScale [1.0, 2.0, 3.0] 2.0
  let out ← forward scaled
  IO.sleep 2
  pure (out.foldl (· + ·) 0.0)

def train (steps : Nat) : IO Unit := do
  for _ in List.range steps do
    let _ ← trainStep
    pure ()
