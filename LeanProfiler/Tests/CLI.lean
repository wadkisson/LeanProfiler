/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfiler.CLI
import LeanProfiler.Tests.Support

/-!
# Command-line interface tests

Checks comparison arguments, exit codes, and generated artifacts.
-/

namespace LeanProfiler.Tests.CLI

open LeanProfiler
open LeanProfiler.CLI
open Lean

abbrev expect := LeanProfiler.Tests.expect "CLI"

def oneEventReport (name : String) (durationNs : Nat) : Report :=
  analyze #[{
    name
    startNs := 10
    endNs := 10 + durationNs
    depth := 0
    index := 0
    threadId := 1
  }]

def writeSummary (path : System.FilePath) (report : Report) : IO Unit :=
  writeJsonFile path (summaryJson report)

def runRoute (args : List String) : IO UInt32 := do
  match ← route args with
  | some code => pure code
  | none => throw <| IO.userError "CLI test expected compare command to be handled"

/-- Run command parsing, exit-code, policy, and JSON-output checks. -/
public def run : IO Unit := do
  let parsed ← IO.ofExcept <| parseCompareOptions [
    "baseline.json", "candidate.json",
    "--metric", "p95_ns",
    "--absolute-tolerance", "50000",
    "--relative-tolerance-bps", "250",
    "--json", "comparison.json",
    "--fail-on-new",
    "--fail-on-missing",
    "--allow-incomplete"
  ]
  expect "all comparison options are parsed"
    (parsed.baselinePath == "baseline.json" &&
      parsed.candidatePath == "candidate.json" &&
      parsed.config.metric == .p95Ns &&
      parsed.config.threshold.absolute == 50000 &&
      parsed.config.threshold.relativeBps == 250 &&
      parsed.jsonPath == some "comparison.json" &&
      parsed.failOnNew &&
      parsed.failOnMissing &&
      parsed.allowIncomplete)
  expect "unknown metrics are rejected"
    (match parseCompareOptions ["a", "b", "--metric", "wall_time"] with
      | .error _ => true
      | .ok _ => false)
  expect "application commands remain unclaimed" ((← route ["run-workload"]).isNone)
  expect "compare help succeeds" ((← runRoute ["compare", "--help"]) == 0)
  expect "Lake argument separator is accepted"
    ((← runRoute ["--", "compare", "--help"]) == 0)

  let directory : System.FilePath := "build/test-artifacts/cli"
  let baselinePath := directory / "baseline.json"
  let candidatePath := directory / "candidate.json"
  let comparisonPath := directory / "comparison.json"
  writeSummary baselinePath (oneEventReport "step" 100)
  writeSummary candidatePath (oneEventReport "step" 120)
  let regressionCode ← runRoute [
    "compare", baselinePath.toString, candidatePath.toString,
    "--metric", "mean_ns",
    "--absolute-tolerance", "10",
    "--relative-tolerance-bps", "500",
    "--json", comparisonPath.toString
  ]
  expect "regression policy returns one" (regressionCode == 1)
  expect "comparison JSON is written" (← comparisonPath.pathExists)
  let comparisonJsonText ← IO.FS.readFile comparisonPath
  let comparisonJsonValue ← IO.ofExcept <| Json.parse comparisonJsonText
  expect "comparison JSON records the failure"
    ((comparisonJsonValue.getObjVal? "has_regression").toOption == some true &&
      (comparisonJsonValue.getObjVal? "policy_failed").toOption == some true &&
      (comparisonJsonValue.getObjVal? "fail_on_new").toOption == some false &&
      (comparisonJsonValue.getObjVal? "allow_incomplete").toOption == some false)

  let toleratedCode ← runRoute [
    "compare", baselinePath.toString, candidatePath.toString,
    "--absolute-tolerance", "25",
    "--relative-tolerance-bps", "500"
  ]
  expect "either tolerance can admit the increase" (toleratedCode == 0)

  let removedPath := directory / "removed.json"
  let addedPath := directory / "added.json"
  writeSummary removedPath (oneEventReport "removed" 100)
  writeSummary addedPath (oneEventReport "added" 100)
  let reportOnlyCode ← runRoute [
    "compare", removedPath.toString, addedPath.toString
  ]
  expect "new and missing rows are report-only by default" (reportOnlyCode == 0)
  let keyPolicyPath := directory / "key-policy.json"
  let failOnNewCode ← runRoute [
    "compare", removedPath.toString, addedPath.toString,
    "--fail-on-new", "--json", keyPolicyPath.toString
  ]
  expect "fail-on-new policy returns one" (failOnNewCode == 1)
  let keyPolicyJson ← IO.ofExcept <| Json.parse (← IO.FS.readFile keyPolicyPath)
  expect "JSON records a key-policy failure"
    ((keyPolicyJson.getObjVal? "has_regression").toOption == some false &&
      (keyPolicyJson.getObjVal? "fail_on_new").toOption == some true &&
      (keyPolicyJson.getObjVal? "policy_failed").toOption == some true)
  let failOnMissingCode ← runRoute [
    "compare", removedPath.toString, addedPath.toString, "--fail-on-missing"
  ]
  expect "fail-on-missing policy returns one" (failOnMissingCode == 1)

  let incompletePath := directory / "incomplete.json"
  let incompleteReport := {
    oneEventReport "step" 100 with
    eventLimit := some 1
    droppedEvents := 3
    issues := #[{ eventIndex := some 0, message := "synthetic validation issue" }]
  }
  writeSummary incompletePath incompleteReport
  let incompleteCode ← runRoute [
    "compare", incompletePath.toString, baselinePath.toString
  ]
  expect "incomplete captures are rejected by default" (incompleteCode == 2)
  let allowedIncompleteCode ← runRoute [
    "compare", incompletePath.toString, baselinePath.toString, "--allow-incomplete"
  ]
  expect "incomplete captures require an explicit override" (allowedIncompleteCode == 0)
  expect "usage errors return two" ((← runRoute ["compare"]) == 2)

end LeanProfiler.Tests.CLI
