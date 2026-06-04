import LeanProfiler

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
