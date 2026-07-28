/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Comparison.Threshold
import Std.Data.HashMap

/-!
# Row matching

Matches complete summary keys and computes the selected metric for each pair.
-/

namespace LeanProfiler

def signedDifference (candidate baseline : Nat) : Int :=
  Int.ofNat candidate - Int.ofNat baseline

def relativeChangeBps (candidate baseline : Nat) : Option Int :=
  if baseline == 0 then
    none
  else if baseline ≤ candidate then
    some <| Int.ofNat (((candidate - baseline) * 10_000) / baseline)
  else
    some <| -Int.ofNat (((baseline - candidate) * 10_000) / baseline)

/-- Compare already-grouped rows by their complete `SummaryKey`. -/
public def compareRows (config : ComparisonConfig) (baseline candidate : Array SummaryRow) :
    PerformanceComparison := Id.run do
  let mut baselineByKey : Std.HashMap SummaryKey SummaryRow := {}
  let mut candidateByKey : Std.HashMap SummaryKey SummaryRow := {}
  for row in baseline do
    baselineByKey := baselineByKey.insert row.key row
  for row in candidate do
    candidateByKey := candidateByKey.insert row.key row
  let mut matched := #[]
  let mut missing := #[]
  let mut newRows := #[]
  for (key, baselineRow) in baselineByKey do
    match candidateByKey[key]? with
    | none =>
        missing := missing.push baselineRow
    | some candidateRow =>
        let baselineValue := config.metric.value baselineRow
        let candidateValue := config.metric.value candidateRow
        matched := matched.push {
          key
          baseline := baselineRow
          candidate := candidateRow
          baselineValue
          candidateValue
          delta := signedDifference candidateValue baselineValue
          changeBps := relativeChangeBps candidateValue baselineValue
          status := classifyMatched config.threshold candidateValue baselineValue
        }
  for (key, candidateRow) in candidateByKey do
    unless baselineByKey.contains key do
      newRows := newRows.push candidateRow
  return {
    config
    matched := matched.qsort fun left right => left.key.lt right.key
    missing := missing.qsort fun left right => left.key.lt right.key
    newRows := newRows.qsort fun left right => left.key.lt right.key
  }

/-- Compare the grouped rows of a baseline and candidate report. -/
public def compareReports (config : ComparisonConfig) (baseline candidate : Report) :
    PerformanceComparison :=
  compareRows config baseline.rows candidate.rows

/-- True when at least one matched row exceeds both regression tolerances. -/
public def PerformanceComparison.hasRegression (comparison : PerformanceComparison) : Bool :=
  comparison.matched.any fun row => row.status == .regression

end LeanProfiler
