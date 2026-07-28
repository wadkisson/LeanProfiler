/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.CLI.Options
import LeanProfiler.Artifact.Read
import LeanProfiler.Comparison.Json
import LeanProfiler.Output.Export

/-!
# Comparison command

Loads two summary artifacts, applies the selected policy, and prints the result.
-/

namespace LeanProfiler.CLI

open LeanProfiler

def comparisonFails (options : CompareOptions)
    (comparison : PerformanceComparison) : Bool :=
  comparison.hasRegression ||
    (options.failOnNew && !comparison.newRows.isEmpty) ||
    (options.failOnMissing && !comparison.missing.isEmpty)

def commandComparisonJson (options : CompareOptions)
    (comparison : PerformanceComparison) : Lean.Json :=
  comparison.toJson
    |>.setObjVal! "fail_on_new" (.bool options.failOnNew)
    |>.setObjVal! "fail_on_missing" (.bool options.failOnMissing)
    |>.setObjVal! "allow_incomplete" (.bool options.allowIncomplete)
    |>.setObjVal! "policy_failed" (.bool (comparisonFails options comparison))

def formatChangeBps : Option Int → String
  | none => "relative change unavailable"
  | some value => s!"change={value} bps"

def printComparison (options : CompareOptions)
    (comparison : PerformanceComparison) : IO Unit := do
  let regressions := comparison.matched.filter fun row => row.status == .regression
  let improvements := comparison.matched.filter fun row => row.status == .improvement
  let withinTolerance := comparison.matched.size - regressions.size - improvements.size
  IO.println (s!"Compared {comparison.matched.size} matched row(s) with "
    ++ s!"metric {options.config.metric.name}; {regressions.size} regression(s), "
    ++ s!"{improvements.size} improvement(s), {withinTolerance} within tolerance.")
  IO.println (s!"Allowed increase: {options.config.threshold.absolute} absolute units and "
    ++ s!"{options.config.threshold.relativeBps} basis points. A matched increase must exceed "
    ++ "both; a zero baseline uses the absolute allowance.")
  for row in regressions do
    IO.println (s!"Regression: {row.key.label}; baseline={row.baselineValue}, "
      ++ s!"candidate={row.candidateValue}, delta={row.delta}, {formatChangeBps row.changeBps}.")
  if !comparison.newRows.isEmpty then
    let policy := if options.failOnNew then "fails this comparison" else "reported only"
    IO.println s!"New rows: {comparison.newRows.size} ({policy})."
    for row in comparison.newRows do
      IO.println s!"  {row.key.label}: {options.config.metric.value row}"
  if !comparison.missing.isEmpty then
    let policy := if options.failOnMissing then "fails this comparison" else "reported only"
    IO.println s!"Missing rows: {comparison.missing.size} ({policy})."
    for row in comparison.missing do
      IO.println s!"  {row.key.label}: {options.config.metric.value row}"

/--
Read two summary artifacts, compare their grouped rows, and return `1` when the selected policy
fails. Invalid or incomplete files raise an `IO.Error` for the command router to report.
-/
public def compareArtifacts (options : CompareOptions) : IO UInt32 := do
  let baseline ← readSummaryArtifact options.baselinePath
  let candidate ← readSummaryArtifact options.candidatePath
  unless options.allowIncomplete do
    for (label, artifact) in [("baseline", baseline), ("candidate", candidate)] do
      let reasons := [
        if artifact.droppedEvents == 0 then none
        else some s!"{artifact.droppedEvents} dropped event(s)",
        if artifact.issues.isEmpty then none
        else some s!"{artifact.issues.size} validation issue(s)"
      ].filterMap id
      unless reasons.isEmpty do
        throw <| IO.userError (s!"{label} summary is incomplete: "
          ++ String.intercalate ", " reasons
          ++ "; pass --allow-incomplete to compare retained rows deliberately")
  let comparison := compareRows options.config baseline.rows candidate.rows
  printComparison options comparison
  if let some path := options.jsonPath then
    writeJsonFile path (commandComparisonJson options comparison)
    IO.println s!"Comparison JSON: {path}"
  pure <| if comparisonFails options comparison then 1 else 0

end LeanProfiler.CLI
