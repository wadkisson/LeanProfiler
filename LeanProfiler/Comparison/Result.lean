/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Comparison.Policy

/-!
# Comparison results

Classifications and row sets produced after two profiler summaries have been matched.
-/

namespace LeanProfiler

/-- Result for a key present in both reports. -/
public inductive MatchedStatus where
  | improvement
  | withinTolerance
  | regression
  deriving Repr, Inhabited, DecidableEq

/-- Stable JSON spelling of a matched-row classification. -/
public def MatchedStatus.name : MatchedStatus → String
  | .improvement => "improvement"
  | .withinTolerance => "within_tolerance"
  | .regression => "regression"

/-- Detailed comparison for one matched structured key. -/
public structure MatchedRow where
  key : SummaryKey
  baseline : SummaryRow
  candidate : SummaryRow
  baselineValue : Nat
  candidateValue : Nat
  delta : Int
  /-- Signed candidate change in basis points, or `none` when the baseline is zero. -/
  changeBps : Option Int
  status : MatchedStatus
  deriving Repr, Inhabited

/--
Comparison of two reports.

`missing` contains baseline rows absent from the candidate. `newRows` contains candidate rows absent
from the baseline. These categories are not automatically failures because instrumentation can
change between captures.
-/
public structure PerformanceComparison where
  config : ComparisonConfig
  matched : Array MatchedRow
  missing : Array SummaryRow
  newRows : Array SummaryRow
  deriving Repr, Inhabited

end LeanProfiler
