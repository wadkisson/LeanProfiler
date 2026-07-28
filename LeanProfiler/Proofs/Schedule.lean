/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Schedule
import Lean.Elab.Tactic.Omega

/-!
# Schedule laws

Boundary conditions for validated profiling schedules.
-/

namespace LeanProfiler

/-- A validated schedule always has a nonempty wait/warmup/active cycle. -/
public theorem Schedule.cycleLength_pos (schedule : Schedule) : 0 < schedule.cycleLength := by
  have hActive : 0 < schedule.active := schedule.activePositive
  unfold Schedule.cycleLength
  omega

/-- Every step in the one-time initial skip interval is classified as `skip`. -/
public theorem Schedule.actionAt_eq_skip_of_lt_skipFirst
    (schedule : Schedule) {step : Nat} (hStep : step < schedule.skipFirst) :
    schedule.actionAt step = .skip := by
  simp [Schedule.actionAt, hStep]

/-- An action that closes a capture also retains the measurements from its current step. -/
public theorem ProfilerAction.records_of_saves
    (action : ProfilerAction) (hSaves : action.saves = true) :
    action.records = true := by
  cases action <;> simp_all [ProfilerAction.saves, ProfilerAction.records]

/--
A finite schedule skips every step at or after the end of its final cycle.

The bound includes the one-time initial skip interval. A repeat count of zero is deliberately
excluded because it denotes an unbounded schedule.
-/
public theorem Schedule.actionAt_eq_skip_of_repeats_finished
    (schedule : Schedule) (hRepeat : 0 < schedule.repeatCount) {step : Nat}
    (hStep :
      schedule.skipFirst + schedule.repeatCount * schedule.cycleLength ≤ step) :
    schedule.actionAt step = .skip := by
  have hLength : 0 < schedule.cycleLength := schedule.cycleLength_pos
  have hPastInitial : ¬step < schedule.skipFirst := by omega
  have hOffset :
      schedule.repeatCount * schedule.cycleLength ≤ step - schedule.skipFirst := by
    omega
  have hCycle :
      schedule.repeatCount ≤ (step - schedule.skipFirst) / schedule.cycleLength :=
    (Nat.le_div_iff_mul_le hLength).2 hOffset
  simp [Schedule.actionAt, hPastInitial, Nat.ne_of_gt hRepeat, hCycle]

end LeanProfiler
