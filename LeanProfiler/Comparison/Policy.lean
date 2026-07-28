/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Comparison.Metric

/-!
# Comparison policy

Configuration for choosing a metric and deciding how much increase a comparison may tolerate.
-/

namespace LeanProfiler

/--
Allowed candidate increase.

`relativeBps` is measured in basis points: 100 basis points is 1 percent. A candidate is a
regression only when its increase is strictly greater than both limits. When the baseline is zero,
the relative limit has no finite denominator, so the absolute limit decides.
-/
public structure RegressionThreshold where
  absolute : Nat := 0
  relativeBps : Nat := 0
  deriving Repr, Inhabited, DecidableEq

/-- Options for one report comparison. Lower values are treated as better. -/
public structure ComparisonConfig where
  metric : ComparisonMetric := .meanNs
  threshold : RegressionThreshold := {}
  deriving Repr, Inhabited, DecidableEq

end LeanProfiler
