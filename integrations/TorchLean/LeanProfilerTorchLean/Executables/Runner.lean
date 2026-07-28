/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

import LeanProfiler.CLI
import LeanProfilerTorchLean.Runner

/-!
Runs LeanProfiler's summary comparison command or a TorchLean model command.
-/

/-- Profile one TorchLean model command using the startup environment configuration. -/
def main (args : List String) : IO UInt32 := do
  match ← LeanProfiler.CLI.route args with
  | some code => pure code
  | none => LeanProfiler.TorchLean.run args
