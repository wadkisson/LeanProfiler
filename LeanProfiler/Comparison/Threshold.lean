/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Comparison.Result

/-!
# Regression thresholds

Pure checks for deciding whether a matched measurement improved, stayed within tolerance, or
regressed.
-/

namespace LeanProfiler

/-- Whether a candidate increase is strictly beyond both configured tolerances. -/
@[expose] public def exceedsThreshold
    (threshold : RegressionThreshold) (candidate baseline : Nat) : Bool :=
  if candidate ≤ baseline then
    false
  else
    let increase := candidate - baseline
    let exceedsAbsolute := threshold.absolute < increase
    let exceedsRelative :=
      baseline == 0 || baseline * threshold.relativeBps < increase * 10_000
    exceedsAbsolute && exceedsRelative

/-- Classify one matched candidate under the convention that smaller measurements are better. -/
@[expose] public def classifyMatched
    (threshold : RegressionThreshold) (candidate baseline : Nat) : MatchedStatus :=
  if candidate < baseline then
    .improvement
  else if exceedsThreshold threshold candidate baseline then
    .regression
  else
    .withinTolerance

end LeanProfiler
