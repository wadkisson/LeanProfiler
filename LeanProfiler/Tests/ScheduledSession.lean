/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfiler.ScheduledSession
import LeanProfiler.Instrumentation
import LeanProfiler.Tests.Support

/-!
# Scheduled session tests

Checks which scheduled steps run, record spans, and write a capture.
-/

namespace LeanProfiler.Tests.ScheduledSession

open LeanProfiler
open LeanProfiler.Internal

abbrev expect := LeanProfiler.Tests.expect "scheduled-session"

def testConfig : ProfilerConfig :=
  {
    enabled := true
    tracePath := "build/test-artifacts/scheduled-cycle-trace.json"
    summaryPath := "build/test-artifacts/scheduled-cycle-summary.json"
    processName := "LeanProfiler schedule test"
  }

/-- Run scheduled capture-boundary and export checks. -/
public def run : IO Unit := do
  let schedule ←
    match Schedule.create 1 1 1 2 1 with
    | .ok schedule => pure schedule
    | .error error => throw <| IO.userError error.message
  let calls ← IO.mkRef (#[] : Array (Nat × ProfilerAction))
  let ran ← runScheduledCycle schedule 0 testConfig "scheduled-cycle" fun step action => do
    calls.modify (·.push (step, action))
    -- The same callback may contain spans for every action. Session activation decides which
    -- interval is retained, so skipped and warmup calls remain ordinary unmeasured work.
    span "scheduled.work" (pure ())
  expect "first finite cycle runs" ran
  expect "callback observes the complete cycle"
    ((← calls.get) == #[
      (0, .skip), (1, .skip), (2, .warmup), (3, .record), (4, .recordAndSave)
    ])
  let events ← capturedEvents
  expect "only active callback spans are retained"
    (events.size == 3 &&
      events[0]!.name == "scheduled-cycle" &&
      events[1]!.name == "scheduled.work" &&
      events[2]!.name == "scheduled.work")
  expect "active spans retain their global step context only when the callback supplies it"
    (events[1]!.parentIndex == some events[0]!.index &&
      events[2]!.parentIndex == some events[0]!.index)
  expect "schedule export restores inactive state" (!(← profilingIsEnabled))

  let previousCalls := (← calls.get).size
  let repeated ← runScheduledCycle schedule 1 testConfig "past-repeat" fun step action =>
    calls.modify (·.push (step, action))
  expect "cycle beyond finite repeat count does not run" (!repeated)
  expect "rejected cycle invokes no callbacks" ((← calls.get).size == previousCalls)

end LeanProfiler.Tests.ScheduledSession
