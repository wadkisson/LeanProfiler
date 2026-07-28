/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

/-!
# Repeated capture schedules

A schedule classifies zero-based steps without reading the clock or changing profiler state. After
an optional initial skip, each cycle contains a wait interval, a warmup interval, and an active
interval. The last active step requests both recording and export.
-/

namespace LeanProfiler

/-- Work requested for one scheduled step. -/
public inductive ProfilerAction where
  /-- Run the step without recording it. -/
  | skip
  /-- Run the workload as warmup without retaining its measurements. -/
  | warmup
  /-- Record the step and keep the current capture open. -/
  | record
  /-- Record the step and finish the current capture afterwards. -/
  | recordAndSave
  deriving Repr, Inhabited, DecidableEq

/-- Configuration error found before a schedule is constructed. -/
public inductive ScheduleError where
  /-- Every cycle needs at least one active step. -/
  | activeMustBePositive
  deriving Repr, Inhabited, DecidableEq

/-- Human-readable explanation of an invalid schedule. -/
public def ScheduleError.message : ScheduleError → String
  | .activeMustBePositive => "a profiling schedule needs at least one active step"

/--
A validated repeated capture schedule.

`skipFirst` applies once. Each later cycle has `wait` skipped steps, `warmup` warmup steps, and
`active` recorded steps. A finite `repeat` limits the number of cycles; zero means no limit.
The proof field prevents direct construction of a schedule with an empty active interval.
-/
public structure Schedule where
  skipFirst : Nat
  wait : Nat
  warmup : Nat
  active : Nat
  repeatCount : Nat
  activePositive : 0 < active

/--
Validate schedule parameters.

Steps are zero-based. `wait`, `warmup`, and `skipFirst` may be zero. `repeatCount = 0` means that
the cycle repeats for as long as the caller supplies steps.
-/
public def Schedule.create (skipFirst wait warmup active repeatCount : Nat := 0) :
    Except ScheduleError Schedule :=
  if positive : 0 < active then
    .ok { skipFirst, wait, warmup, active, repeatCount, activePositive := positive }
  else
    .error .activeMustBePositive

/-- Number of steps in one wait/warmup/active cycle. -/
@[expose] public def Schedule.cycleLength (schedule : Schedule) : Nat :=
  schedule.wait + schedule.warmup + schedule.active

/--
Classify a zero-based step.

After `skipFirst`, cycle `0` begins. A finite repeat count returns `skip` after its final cycle.
Within a cycle, the final active step is `recordAndSave`; this also handles `active = 1`.
-/
@[expose] public def Schedule.actionAt (schedule : Schedule) (step : Nat) : ProfilerAction :=
  if step < schedule.skipFirst then
    .skip
  else
    let offset := step - schedule.skipFirst
    let length := schedule.cycleLength
    let cycle := offset / length
    if schedule.repeatCount != 0 && schedule.repeatCount ≤ cycle then
      .skip
    else
      let position := offset % length
      if position < schedule.wait then
        .skip
      else if position < schedule.wait + schedule.warmup then
        .warmup
      else if position + 1 == length then
        .recordAndSave
      else
        .record

/-- Whether an action retains measurements from its step. -/
@[expose] public def ProfilerAction.records : ProfilerAction → Bool
  | .record | .recordAndSave => true
  | .skip | .warmup => false

/-- Whether an action closes and exports the current capture. -/
@[expose] public def ProfilerAction.saves : ProfilerAction → Bool
  | .recordAndSave => true
  | .skip | .warmup | .record => false

end LeanProfiler
