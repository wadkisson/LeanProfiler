/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfilerTorchLean.MlpTraining

/-!
# TorchLean MLP executable

Runs the reusable MLP workload with LeanProfiler's environment configuration.
-/

/-- Entry point for the TorchLean MLP profiling example. -/
public def main : IO Unit :=
  LeanProfiler.TorchLean.MlpTraining.run LeanProfiler.startupConfig
