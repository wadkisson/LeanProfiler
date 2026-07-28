/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfiler

/-!
# Scheduled steps

Runs one profiling cycle. Skipped and warmup steps execute before the session starts. The capture
contains the active interval and is exported after its final `recordAndSave` step.
-/

namespace LeanProfiler.Examples.ScheduledSteps

/-- Schedule and workload inputs for the example loop. -/
structure WorkloadConfig where
  skipFirst : Nat := 1
  wait : Nat := 1
  warmup : Nat := 1
  active : Nat := 2
  delayMs : UInt32 := 2
  captureName : String := "example.scheduled-steps"

/-- Simulate one model step for the configured duration. -/
def runModelStep (config : WorkloadConfig) : IO Unit :=
  IO.sleep config.delayMs

/-- Validate the schedule stored in the example's workload configuration. -/
def makeSchedule (config : WorkloadConfig) : IO Schedule :=
  match Schedule.create config.skipFirst config.wait config.warmup config.active 1 with
  | .ok schedule => pure schedule
  | .error error => throw <| IO.userError error.message

/-- Apply a finite schedule to real work and record only its active interval. -/
def run (profiler : ProfilerConfig) (workload : WorkloadConfig := {}) : IO Unit := do
  let schedule ← makeSchedule workload
  let _ ← runScheduledCycle schedule 0 profiler workload.captureName fun step action =>
    if action.records then
      withStep step do
        span "training.step" (runModelStep workload) (metadata := {
          phase := some "train"
          activity := some (if action.saves then "record and save" else "record")
        })
    else
      runModelStep workload
  pure ()

end LeanProfiler.Examples.ScheduledSteps

/-- Run the scheduled-step example with the environment configuration. -/
public def main : IO Unit :=
  LeanProfiler.Examples.ScheduledSteps.run LeanProfiler.startupConfig
