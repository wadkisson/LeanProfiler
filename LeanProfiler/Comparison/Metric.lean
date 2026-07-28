/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Analysis.Report

/-!
# Comparison metrics

Names, parsing, and row selection for the counters accepted by report comparisons.
-/

namespace LeanProfiler

/-- Summary statistic used to compare matching rows. All choices are nonnegative counters. -/
public inductive ComparisonMetric where
  | totalNs
  | selfNs
  | meanNs
  | medianNs
  | p95Ns
  | maxNs
  | totalHeartbeats
  | selfHeartbeats
  | allocBytes
  | peakLiveBytes
  deriving Repr, Inhabited, DecidableEq

/-- Stable command-line and JSON spelling of a comparison metric. -/
public def ComparisonMetric.name : ComparisonMetric → String
  | .totalNs => "total_ns"
  | .selfNs => "self_ns"
  | .meanNs => "mean_ns"
  | .medianNs => "median_ns"
  | .p95Ns => "p95_ns"
  | .maxNs => "max_ns"
  | .totalHeartbeats => "total_heartbeats"
  | .selfHeartbeats => "self_heartbeats"
  | .allocBytes => "alloc_bytes"
  | .peakLiveBytes => "peak_live_bytes"

/-- Parse the stable command-line and JSON spelling of a comparison metric. -/
public def ComparisonMetric.parse (value : String) : Except String ComparisonMetric :=
  match value with
  | "total_ns" => pure .totalNs
  | "self_ns" => pure .selfNs
  | "mean_ns" => pure .meanNs
  | "median_ns" => pure .medianNs
  | "p95_ns" => pure .p95Ns
  | "max_ns" => pure .maxNs
  | "total_heartbeats" => pure .totalHeartbeats
  | "self_heartbeats" => pure .selfHeartbeats
  | "alloc_bytes" => pure .allocBytes
  | "peak_live_bytes" => pure .peakLiveBytes
  | _ =>
      throw (s!"unknown metric `{value}`; expected total_ns, self_ns, mean_ns, median_ns, "
        ++ "p95_ns, max_ns, total_heartbeats, self_heartbeats, alloc_bytes, or "
        ++ "peak_live_bytes")

/-- Select the counter represented by `metric` from a grouped row. -/
public def ComparisonMetric.value (metric : ComparisonMetric) (row : SummaryRow) : Nat :=
  match metric with
  | .totalNs => row.totalNs
  | .selfNs => row.selfNs
  | .meanNs => row.meanNs
  | .medianNs => row.medianNs
  | .p95Ns => row.p95Ns
  | .maxNs => row.maxNs
  | .totalHeartbeats => row.totalHeartbeats
  | .selfHeartbeats => row.selfHeartbeats
  | .allocBytes => row.allocBytes
  | .peakLiveBytes => row.peakLiveBytes

end LeanProfiler
