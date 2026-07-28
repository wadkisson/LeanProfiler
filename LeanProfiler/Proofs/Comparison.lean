/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Comparison

/-!
# Comparison laws

Laws for comparisons in which smaller measurements are better.
-/

namespace LeanProfiler

/-- A candidate at or below its baseline never exceeds a regression threshold. -/
public theorem exceedsThreshold_eq_false_of_le
    (threshold : RegressionThreshold) {candidate baseline : Nat}
    (hCandidate : candidate ≤ baseline) :
    exceedsThreshold threshold candidate baseline = false := by
  simp [exceedsThreshold, hCandidate]

/-- Exceeding a regression threshold entails a strict increase over the baseline. -/
public theorem baseline_lt_candidate_of_exceedsThreshold
    (threshold : RegressionThreshold) {candidate baseline : Nat}
    (hThreshold : exceedsThreshold threshold candidate baseline = true) :
    baseline < candidate := by
  by_cases hCandidate : candidate ≤ baseline
  · rw [exceedsThreshold_eq_false_of_le threshold hCandidate] at hThreshold
    contradiction
  · exact Nat.lt_of_not_ge hCandidate

/-- Classification reports an improvement exactly when the candidate is strictly smaller. -/
public theorem classifyMatched_eq_improvement_iff
    (threshold : RegressionThreshold) (candidate baseline : Nat) :
    classifyMatched threshold candidate baseline = .improvement ↔ candidate < baseline := by
  constructor
  · intro hStatus
    by_cases hImprovement : candidate < baseline
    · exact hImprovement
    · simp only [classifyMatched, hImprovement, ↓reduceIte] at hStatus
      split at hStatus <;> contradiction
  · intro hImprovement
    simp [classifyMatched, hImprovement]

/-- A classified regression is necessarily a strict increase over the baseline. -/
public theorem baseline_lt_candidate_of_classifyMatched_eq_regression
    (threshold : RegressionThreshold) {candidate baseline : Nat}
    (hStatus : classifyMatched threshold candidate baseline = .regression) :
    baseline < candidate := by
  simp only [classifyMatched] at hStatus
  split at hStatus
  · contradiction
  · split at hStatus
    · exact baseline_lt_candidate_of_exceedsThreshold threshold (by assumption)
    · contradiction

/-- A candidate at or below its baseline cannot be classified as a regression. -/
public theorem classifyMatched_ne_regression_of_le
    (threshold : RegressionThreshold) {candidate baseline : Nat}
    (hCandidate : candidate ≤ baseline) :
    classifyMatched threshold candidate baseline ≠ .regression := by
  intro hStatus
  have hIncrease :=
    baseline_lt_candidate_of_classifyMatched_eq_regression threshold hStatus
  exact (Nat.not_lt_of_ge hCandidate) hIncrease

end LeanProfiler
