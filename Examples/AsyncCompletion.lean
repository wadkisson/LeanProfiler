/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfiler

/-!
# Completion hooks

The action in this example launches work on another Lean task. Its completion hook waits for that
task before the span's stop timestamp, mirroring the synchronization boundary a device adapter
would provide.
-/

namespace LeanProfiler.Examples.AsyncCompletion

/-- Delay used by the asynchronous example worker. -/
structure WorkloadConfig where
  workerDelayMs : UInt32 := 8

/-- Convert a task's explicit `Except` result back into an ordinary `IO` result. -/
def awaitWorker (worker : Task (Except IO.Error Unit)) : IO Unit := do
  match ← IO.wait worker with
  | .ok _ => pure ()
  | .error error => throw error

/-- Wait for the worker installed by the timed action before taking its stop timestamp. -/
def completionHooks
    (pending : IO.Ref (Option (Task (Except IO.Error Unit)))) : SpanHooks :=
  {
    State := Unit
    prepare := pure ()
    completeTiming := fun _ => do
      if let some worker ← pending.get then
        awaitWorker worker
  }

/--
Launch one worker task and include its completion in the recorded elapsed time.

The reference connects the action to the hook without putting task setup before the start timestamp.
-/
def run (profiler : ProfilerConfig) (workload : WorkloadConfig := {}) : IO Unit :=
  profile profiler "example.async-completion" do
    let pending ← IO.mkRef (none : Option (Task (Except IO.Error Unit)))
    let hooks := completionHooks pending
    span "worker.complete" (do
      let worker ← IO.asTask (IO.sleep workload.workerDelayMs)
      pending.set (some worker)
    ) (metadata := {
      activity := some "asynchronous work"
      timing := some "completion"
    }) (hooks := hooks)

end LeanProfiler.Examples.AsyncCompletion

/-- Run the asynchronous-completion example with the environment configuration. -/
public def main : IO Unit :=
  LeanProfiler.Examples.AsyncCompletion.run LeanProfiler.startupConfig
