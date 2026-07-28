/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Schedule
public import LeanProfiler.Sugar

/-!
# Scheduled profiling sessions

Wait and warmup work run with instrumentation disabled. The capture contains the active interval
and is exported after its final `recordAndSave` step.
-/

namespace LeanProfiler

/--
Run one complete schedule cycle.

The callback receives its zero-based global step and the action selected by the schedule. Cycle
zero also runs `skipFirst`; later cycles begin at their wait interval. The function returns `false`
without running work when `cycle` lies beyond a finite repeat count.

Each completed cycle writes `config.tracePath` and `config.summaryPath`. A caller running multiple
cycles should therefore provide distinct paths for each invocation when earlier reports must be
retained.
-/
public def runScheduledCycle (schedule : Schedule) (cycle : Nat) (config : ProfilerConfig)
    (captureName : String) (runStep : Nat → ProfilerAction → IO Unit) : IO Bool := do
  if schedule.repeatCount != 0 && schedule.repeatCount ≤ cycle then
    return false
  let cycleStart := schedule.skipFirst + cycle * schedule.cycleLength
  let firstStep := if cycle == 0 then 0 else cycleStart
  let activeStart := cycleStart + schedule.wait + schedule.warmup
  for offset in List.range (activeStart - firstStep) do
    let step := firstStep + offset
    runStep step (schedule.actionAt step)
  profile config captureName do
    for offset in List.range schedule.active do
      let step := activeStart + offset
      runStep step (schedule.actionAt step)
  return true

end LeanProfiler
