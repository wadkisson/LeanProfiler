/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

import LeanProfiler.CLI

/-!
The standalone executable compares summary artifacts written by profiled applications.
-/

/-- Run the standalone LeanProfiler command router. -/
def main (args : List String) : IO UInt32 := do
  match ← LeanProfiler.CLI.route args with
  | some code => pure code
  | none => do
      if args.isEmpty || args == ["--help"] || args == ["-h"] then
        IO.println LeanProfiler.CLI.usage
        pure 0
      else
        IO.eprintln s!"leanprofiler: unknown command `{String.intercalate " " args}`"
        IO.eprintln LeanProfiler.CLI.usage
        pure 2
