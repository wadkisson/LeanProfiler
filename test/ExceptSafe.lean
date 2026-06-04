import LeanProfiler

set_option profiler.rewrite true

/-- Must not be rewritten (`Except` return is skipped). -/
def parseFlags (args : List String) : Except String (Nat × List String) := do
  match args with
  | [] => throw "missing flag"
  | n :: rest => pure (n.length, rest)

def useParse : IO Unit := do
  match parseFlags ["ok", "rest"] with
  | .error e => IO.eprintln e
  | .ok (n, rest) => IO.println s!"{n} {rest}"

def main : IO UInt32 := do
  useParse
  pure 0
