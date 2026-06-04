import LeanProfiler

set_option profiler.rewrite true

@[profile]
def pulse (_tag : String) (ms : Nat) : IO Unit := do
  IO.sleep ms.toUInt32
  pure ()

@[profile]
def emit (lbl : String) (msg : String) : IO Unit := do
  pulse s!"emit.{lbl}" 1
  IO.println s!"[{lbl}] {msg}"

def forEachIdx (n : Nat) (f : Nat → IO Unit) : IO Unit := do
  for i in List.range n do
    f i

def forEachPair (n m : Nat) (f : Nat → Nat → IO Unit) : IO Unit := do
  for i in List.range n do
    for j in List.range m do
      f i j
