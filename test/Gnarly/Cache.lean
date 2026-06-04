import LeanProfiler
import test.Gnarly.Core
import test.Gnarly.Graph

@[profile]
def cacheProbe (key : Nat) : IO Bool := do
  pulse s!"cache.probe.{key % 4}" 1
  pure (key % 3 == 0)

@[profile]
def cacheFill (key : Nat) (value : Nat) : IO Unit := do
  pulse s!"cache.fill.{key}" 2
  emit "cache" s!"stored {key}={value}"

@[profile]
def cacheGetOrCompute (key : Nat) : IO Nat := do
  let hit ← cacheProbe key
  if hit then
    pulse s!"cache.hit.{key}" 1
    pure (key * 7)
  else
    let v ← walkGraph (key % 9) 2
    cacheFill key v
    pure v

@[profile]
def warmCache (keys : List Nat) : IO Nat := do
  let mut sum := 0
  for k in keys do
    let v ← cacheGetOrCompute k
    sum := sum + v
  pure sum

@[profile]
def cacheStress (rounds : Nat) : IO Nat := do
  let mut total := 0
  for r in List.range rounds do
    let keys := (List.range 8).map (fun i => r * 10 + i)
    let s ← warmCache keys
    total := total + s
  pure total
