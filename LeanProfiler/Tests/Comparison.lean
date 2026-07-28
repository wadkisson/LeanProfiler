/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfiler.Comparison
import LeanProfiler.Tests.Support

/-!
# Performance comparison tests

Checks row matching, thresholds, classifications, and JSON output.
-/

namespace LeanProfiler.Tests.Comparison

open LeanProfiler
open Lean

abbrev expect := LeanProfiler.Tests.expect "comparison"

def allMetrics : Array ComparisonMetric :=
  #[
    .totalNs,
    .selfNs,
    .meanNs,
    .medianNs,
    .p95Ns,
    .maxNs,
    .totalHeartbeats,
    .selfHeartbeats,
    .allocBytes,
    .peakLiveBytes
  ]

def row (name : String) (meanNs : Nat) (phase : Option String := none) : SummaryRow :=
  {
    key := { name, phase }
    totalNs := meanNs * 2
    selfNs := meanNs * 2
    calls := 2
    minNs := meanNs
    meanNs
    medianNs := meanNs
    p95Ns := meanNs
    maxNs := meanNs
    totalHeartbeats := meanNs / 2
    selfHeartbeats := meanNs / 2
    sharePermille := 0
    allocBytes := meanNs * 4
    peakLiveBytes := meanNs * 3
    allocDeltaBytes := 0
  }

/-- Run report comparison and metric spelling checks. -/
public def run : IO Unit := do
  for metric in allMetrics do
    expect s!"metric `{metric.name}` has a name/parse round trip"
      (match ComparisonMetric.parse metric.name with
      | .ok parsed => parsed == metric
      | .error _ => false)

  let config : ComparisonConfig := {
    metric := .meanNs
    threshold := { absolute := 10, relativeBps := 1000 }
  }
  let comparison := compareRows config
    #[row "regressed" 100, row "boundary" 100, row "faster" 100, row "removed" 50]
    #[row "regressed" 111, row "boundary" 110, row "faster" 80, row "added" 70]

  expect "three keys matched" (comparison.matched.size == 3)
  expect "baseline-only row is missing"
    (comparison.missing.size == 1 && comparison.missing[0]!.key.name == "removed")
  expect "candidate-only row is new"
    (comparison.newRows.size == 1 && comparison.newRows[0]!.key.name == "added")
  expect "both tolerances exceeded"
    (comparison.matched.any fun result =>
      result.key.name == "regressed" &&
        result.status == .regression &&
        result.delta == 11 &&
        result.changeBps == some 1100)
  expect "threshold boundary is allowed"
    (comparison.matched.any fun result =>
      result.key.name == "boundary" && result.status == .withinTolerance)
  expect "lower candidate is an improvement"
    (comparison.matched.any fun result =>
      result.key.name == "faster" &&
        result.status == .improvement &&
        result.changeBps == some (-2000))
  expect "regression summary" comparison.hasRegression

  let zeroBaseline := compareRows
    { metric := .meanNs, threshold := { absolute := 5, relativeBps := 9000 } }
    #[row "zero" 0] #[row "zero" 6]
  expect "absolute tolerance decides a zero baseline"
    (zeroBaseline.matched[0]!.status == .regression &&
      zeroBaseline.matched[0]!.changeBps.isNone)

  let structured := compareRows {}
    #[row "same" 10 (some "forward")]
    #[row "same" 12 (some "backward")]
  expect "full structured key controls matching"
    (structured.matched.isEmpty && structured.missing.size == 1 && structured.newRows.size == 1)

  let encoded := Json.compress comparison.toJson
  expect "comparison JSON parses" (Json.parse encoded).isOk
  expect "comparison JSON records metric and status"
    (encoded.contains "\"metric\":\"mean_ns\"" && encoded.contains "\"status\":\"regression\"")

end LeanProfiler.Tests.Comparison
