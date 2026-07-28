/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfiler.Schedule
import LeanProfiler.Tests.Support

/-!
# Capture schedule tests

Checks schedule validation and step classification at cycle boundaries.
-/

namespace LeanProfiler.Tests.Schedule

open LeanProfiler

abbrev expect := LeanProfiler.Tests.expect "schedule"

def requireSchedule (skipFirst wait warmup active repeatCount : Nat) : IO Schedule :=
  match Schedule.create skipFirst wait warmup active repeatCount with
  | .ok schedule => pure schedule
  | .error error => throw <| IO.userError error.message

/-- Run schedule validation and cycle-boundary checks. -/
public def run : IO Unit := do
  expect "empty active interval is rejected" <|
    match Schedule.create 0 0 0 0 1 with
    | .error .activeMustBePositive => true
    | _ => false

  let schedule ← requireSchedule 2 1 2 3 2
  let expected : Array ProfilerAction := #[
    .skip, .skip,
    .skip, .warmup, .warmup, .record, .record, .recordAndSave,
    .skip, .warmup, .warmup, .record, .record, .recordAndSave,
    .skip, .skip
  ]
  let actual := Array.range expected.size |>.map schedule.actionAt
  expect "initial skip and two complete cycles" (actual == expected)
  expect "cycle length" (schedule.cycleLength == 6)

  let singleActive ← requireSchedule 0 0 0 1 0
  expect "single active step saves every unbounded cycle"
    ((Array.range 4).all fun step => singleActive.actionAt step == .recordAndSave)

  let noWarmup ← requireSchedule 0 1 0 2 1
  expect "zero-length warmup is skipped"
    ((Array.range 4).map noWarmup.actionAt ==
      #[.skip, .record, .recordAndSave, .skip])

  expect "record action retains without saving"
    (ProfilerAction.record.records && !ProfilerAction.record.saves)
  expect "final action retains and saves"
    (ProfilerAction.recordAndSave.records && ProfilerAction.recordAndSave.saves)
  expect "warmup neither retains nor saves"
    (!ProfilerAction.warmup.records && !ProfilerAction.warmup.saves)

end LeanProfiler.Tests.Schedule
