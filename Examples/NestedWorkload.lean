/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler

/-!
# Nested example workload

Shared workload used by the introductory trace and regression walkthrough.
-/

namespace LeanProfiler.Examples.NestedWorkload

/-- Step count and delays for the nested-span example. -/
public structure WorkloadConfig where
  steps : Nat := 3
  loadDelayMs : UInt32 := 2
  forwardDelayMs : UInt32 := 4

/-- Record one input and forward pair under shared step context. -/
def runStep (config : WorkloadConfig) (step : Nat) : IO Unit :=
  withStep step do
    span "input.load" (IO.sleep config.loadDelayMs) (metadata := {
      phase := some "input"
      activity := some "load"
    })
    withModule "encoder.block" do
      withPhase "forward" do
        span "model.forward" (IO.sleep config.forwardDelayMs)

/-- Run the example workload under one profiling session. -/
public def run (profiler : ProfilerConfig) (workload : WorkloadConfig := {}) : IO Unit :=
  profile profiler "example.nested-spans" do
    for step in List.range workload.steps do
      runStep workload step

end LeanProfiler.Examples.NestedWorkload
