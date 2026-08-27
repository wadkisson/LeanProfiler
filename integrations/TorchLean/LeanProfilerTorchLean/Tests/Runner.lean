/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfilerTorchLean.CommandMetadata
import LeanProfilerTorchLean.Runner

/-!
# TorchLean runner tests

Exercises the runner's help path without starting a model workload.
-/

namespace LeanProfilerTorchLean.Tests.Runner

/-- Throw when a pure runner-metadata check fails. -/
def expect (label : String) (condition : Bool) : IO Unit :=
  unless condition do
    throw <| IO.userError s!"runner metadata test failed: {label}"

/-- Check that the integration delegates recognized and unknown model commands correctly. -/
public def run : IO Unit := do
  let splitArgs :=
    ["quickstart_mlp", "--device", "cuda", "--execution=eager", "--scalar", "float32"]
  let metadata := LeanProfiler.TorchLean.CommandMetadata.fromArguments splitArgs
  expect "split device flag" (metadata.device == some "cuda")
  expect "inline execution flag" (metadata.backend == some "eager")
  expect "split scalar flag" (metadata.dtype == some "float32")
  expect "CUDA selection" (LeanProfiler.TorchLean.CommandMetadata.usesCuda splitArgs)
  expect "CPU does not select CUDA"
    (!LeanProfiler.TorchLean.CommandMetadata.usesCuda ["--device=cpu"])
  let exitCode ← LeanProfiler.TorchLean.run ["--help"]
  unless exitCode == 0 do
    throw <| IO.userError s!"TorchLean runner returned {exitCode} for --help"

end LeanProfilerTorchLean.Tests.Runner
