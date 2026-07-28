/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import Examples.NestedWorkload
import LeanProfiler

/-!
# Regression walkthrough

Records baseline and candidate runs of the same nested workload, then compares their p95 values.
The candidate changes only the delay inside `model.forward`, so the expected regression has a known
source.
-/

namespace LeanProfiler.Examples.RegressionWalkthrough

open Lean
open LeanProfiler

def artifactDirectory : System.FilePath :=
  "build" / "regression-walkthrough"

def profilerConfig (stem processName : String) : ProfilerConfig :=
  {
    enabled := true
    tracePath := artifactDirectory / s!"{stem}-trace.json"
    summaryPath := artifactDirectory / s!"{stem}-summary.json"
    processName
  }

def comparisonConfig : ComparisonConfig :=
  {
    metric := .p95Ns
    threshold := {
      absolute := 500_000
      relativeBps := 1000
    }
  }

/-- Record both runs, compare their grouped rows, and retain every artifact. -/
public def run : IO Unit := do
  IO.FS.createDirAll artifactDirectory
  NestedWorkload.run
    (profilerConfig "baseline" "LeanProfiler regression baseline")
    { steps := 3, loadDelayMs := 2, forwardDelayMs := 4 }
  NestedWorkload.run
    (profilerConfig "candidate" "LeanProfiler regression candidate")
    { steps := 3, loadDelayMs := 2, forwardDelayMs := 10 }

  let baseline ← readSummaryArtifact (artifactDirectory / "baseline-summary.json")
  let candidate ← readSummaryArtifact (artifactDirectory / "candidate-summary.json")
  let comparison := compareRows comparisonConfig baseline.rows candidate.rows
  let comparisonPath := artifactDirectory / "comparison.json"
  IO.FS.writeFile comparisonPath (Json.pretty comparison.toJson ++ "\n")

  unless comparison.hasRegression do
    throw <| IO.userError "expected the slower model.forward candidate to be a regression"
  let regressionCount :=
    (comparison.matched.filter fun row => row.status == .regression).size
  IO.println s!"Recorded baseline and candidate under {artifactDirectory}"
  IO.println s!"Detected {regressionCount} regressed rows with metric p95_ns"
  IO.println s!"Comparison: {comparisonPath}"

end LeanProfiler.Examples.RegressionWalkthrough

/-- Run the complete baseline-to-comparison walkthrough. -/
public def main : IO Unit :=
  LeanProfiler.Examples.RegressionWalkthrough.run
