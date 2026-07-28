/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler

/-!
# Nested example workload

Shared source-indexing workload used by the introductory trace and regression walkthrough.
-/

namespace LeanProfiler.Examples.NestedWorkload

/-- Source count and phase delays for the nested-span example. -/
public structure WorkloadConfig where
  steps : Nat := 3
  readDelayMs : UInt32 := 2
  analyzeDelayMs : UInt32 := 4

/-- Record reading and analyzing one source under shared step context. -/
def runStep (config : WorkloadConfig) (step : Nat) : IO Unit :=
  withStep step do
    span "source.read" (IO.sleep config.readDelayMs) (metadata := {
      phase := some "read"
      activity := some "filesystem"
    })
    withModule "indexer" do
      withPhase "analysis" do
        span "source.analyze" (IO.sleep config.analyzeDelayMs)

/-- Run the example workload under one profiling session. -/
public def run (profiler : ProfilerConfig) (workload : WorkloadConfig := {}) : IO Unit :=
  profile profiler "example.source-indexer" do
    for step in List.range workload.steps do
      runStep workload step

end LeanProfiler.Examples.NestedWorkload
