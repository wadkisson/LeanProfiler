/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Comparison.Match
public import Lean.Data.Json
import LeanProfiler.Internal.Json

/-!
# Comparison JSON

Machine-readable output for CI and benchmark archives.
-/

namespace LeanProfiler

def matchedRowJson (row : MatchedRow) : Lean.Json :=
  Lean.Json.mkObj [
    ("key", Internal.Json.summaryKey row.key),
    ("status", .str row.status.name),
    ("baseline", Internal.Json.nat row.baselineValue),
    ("candidate", Internal.Json.nat row.candidateValue),
    ("delta", Internal.Json.int row.delta),
    ("change_bps", Internal.Json.option Internal.Json.int row.changeBps),
    ("baseline_calls", Internal.Json.nat row.baseline.calls),
    ("candidate_calls", Internal.Json.nat row.candidate.calls)
  ]

def unmatchedRowJson (metric : ComparisonMetric) (row : SummaryRow) : Lean.Json :=
  Lean.Json.mkObj [
    ("key", Internal.Json.summaryKey row.key),
    ("value", Internal.Json.nat (metric.value row)),
    ("calls", Internal.Json.nat row.calls)
  ]

/-- Stable JSON representation suitable for a CI artifact. -/
public def PerformanceComparison.toJson (comparison : PerformanceComparison) : Lean.Json :=
  Lean.Json.mkObj [
    ("schema_version", Internal.Json.nat 1),
    ("metric", .str comparison.config.metric.name),
    ("absolute_tolerance", Internal.Json.nat comparison.config.threshold.absolute),
    ("relative_tolerance_bps", Internal.Json.nat comparison.config.threshold.relativeBps),
    ("has_regression", .bool comparison.hasRegression),
    ("matched", .arr (comparison.matched.map matchedRowJson)),
    ("missing", .arr (comparison.missing.map (unmatchedRowJson comparison.config.metric))),
    ("new", .arr (comparison.newRows.map (unmatchedRowJson comparison.config.metric)))
  ]

end LeanProfiler
