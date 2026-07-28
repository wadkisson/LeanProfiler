/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfiler.Proofs

/-!
# Proof API compile tests

Compile checks for theorem names, implicit arguments, and proof imports.
-/

namespace LeanProfiler.Tests.Proofs

open LeanProfiler

/-- A save request can be used wherever retaining the current step is required. -/
example (action : ProfilerAction) (hSaves : action.saves = true) :
    action.records = true :=
  action.records_of_saves hSaves

/-- Initial-skip classification is available for an arbitrary validated schedule. -/
example (schedule : Schedule) (step : Nat) (hStep : step < schedule.skipFirst) :
    schedule.actionAt step = .skip :=
  schedule.actionAt_eq_skip_of_lt_skipFirst hStep

/-- A nonincreasing candidate can be discharged without inspecting tolerance values. -/
example (threshold : RegressionThreshold) (candidate baseline : Nat)
    (hCandidate : candidate ≤ baseline) :
    classifyMatched threshold candidate baseline ≠ .regression :=
  classifyMatched_ne_regression_of_le threshold hCandidate

/-- Consumers of analyzed timings can recover the exclusive-time bound directly. -/
example (events : Array Event) (timing : EventTiming)
    (hTiming : timing ∈ (analyze events).timings) :
    timing.selfNs ≤ timing.inclusiveNs :=
  selfNs_le_inclusiveNs_of_mem_analyze events timing hTiming

end LeanProfiler.Tests.Proofs
