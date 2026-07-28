/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

import LeanProfilerTorchLean.Tests.Runner
import LeanProfilerTorchLean.Tests.MlpTraining

/-!
# TorchLean integration test runner

Runs the command-dispatch smoke test and the small MLP workload checks.
-/

/-- Run every TorchLean integration test suite. -/
def main : IO Unit := do
  LeanProfilerTorchLean.Tests.Runner.run
  LeanProfilerTorchLean.Tests.MlpTraining.run
  IO.println "LeanProfiler TorchLean integration tests passed"
