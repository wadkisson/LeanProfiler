/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfiler.Artifact
import LeanProfiler.Comparison
import LeanProfiler.Tests.Support

/-!
# Summary artifact tests

Checks strict decoding and cross-field validation for saved summaries.
-/

namespace LeanProfiler.Tests.Artifact

open LeanProfiler
open Lean

abbrev expect := LeanProfiler.Tests.expect "artifact"

def expectError (label needle : String) (result : Except String α) : IO Unit :=
  match result with
  | .ok _ => throw <| IO.userError s!"artifact test failed: {label} was accepted"
  | .error message =>
      expect label (message.contains needle)

def sampleReport : Report :=
  let event : Event := {
    name := "model.forward"
    startNs := 100
    endNs := 350
    depth := 0
    index := 0
    threadId := 17
    heartbeats := 31
    metadata := {
      phase := some "forward"
      activity := some "host"
      backend := some "eager"
      dtype := some "float32"
      device := some "cpu"
      moduleName := some "encoder"
      allocBytes := some 80
      allocPeakBytes := some 200
      allocDeltaBytes := some (-3)
    }
  }
  {
    analyze #[event] with
    process := some {
      userCpuMs := 2
      systemCpuMs := 1
      peakResidentSetSizeKb := 4096
      peakResidentSetIncreaseKb := 128
      minorPageFaults := 3
      majorPageFaults := 0
      blockInputOps := 1
      blockOutputOps := 2
      voluntaryContextSwitches := 4
      involuntaryContextSwitches := 1
    }
    eventLimit := some 1
    droppedEvents := 2
  }

def setFirstArrayObjectField (document : Json) (arrayField objectField : String)
    (value : Json) : Json :=
  let items := (document.getObjVal? arrayField).toOption.get!.getArr?.toOption.get!
  let item := items[0]!
  document.setObjVal! arrayField (.arr (items.set! 0 (item.setObjVal! objectField value)))

/-- Run summary decoding, validation, and comparison compatibility checks. -/
public def run : IO Unit := do
  let encoded := summaryJson sampleReport
  let artifact ← IO.ofExcept (parseSummaryArtifact encoded)
  expect "header fields survive encoding and decoding"
    (artifact.eventCount == 1 &&
      artifact.threadCount == 1 &&
      artifact.traceOriginNs == 100 &&
      artifact.traceWindowNs == 250 &&
      artifact.recordedThreadNs == 250 &&
      artifact.eventLimit == some 1 &&
      artifact.droppedEvents == 2)
  expect "event timing survives encoding and decoding"
    (artifact.eventTimings == #[{
      eventIndex := 0
      inclusiveNs := 250
      selfNs := 250
      inclusiveHeartbeats := 31
      selfHeartbeats := 31
    }])
  expect "complete grouping key is decoded"
    (artifact.rows.size == 1 &&
      artifact.rows[0]!.key.name == "model.forward" &&
      artifact.rows[0]!.key.phase == some "forward" &&
      artifact.rows[0]!.key.activity == some "host" &&
      artifact.rows[0]!.key.backend == some "eager" &&
      artifact.rows[0]!.key.dtype == some "float32" &&
      artifact.rows[0]!.key.device == some "cpu" &&
      artifact.rows[0]!.key.moduleName == some "encoder")
  expect "complete summary row is decoded"
    (artifact.rows[0]!.calls == 1 &&
      artifact.rows[0]!.totalNs == 250 &&
      artifact.rows[0]!.selfNs == 250 &&
      artifact.rows[0]!.meanNs == 250 &&
      artifact.rows[0]!.p95Ns == 250 &&
      artifact.rows[0]!.allocBytes == 80 &&
      artifact.rows[0]!.peakLiveBytes == 200 &&
      artifact.rows[0]!.allocDeltaBytes == -3)
  expect "process counters are decoded"
    (artifact.process.any fun metrics =>
      metrics.userCpuMs == 2 &&
        metrics.peakResidentSetSizeKb == 4096 &&
        metrics.voluntaryContextSwitches == 4)

  let path : System.FilePath := "build/test-artifacts/summary-round-trip.json"
  writeJsonFile path encoded
  let fromFile ← readSummaryArtifact path
  expect "written summary can be read in a separate step"
    (fromFile.rows[0]!.key == artifact.rows[0]!.key &&
      fromFile.eventTimings == artifact.eventTimings)
  let selfComparison := compareRows
    { metric := .totalNs, threshold := {} }
    artifact.rows fromFile.rows
  expect "decoded rows feed report comparison without adaptation"
    (selfComparison.matched.size == artifact.rows.size &&
      selfComparison.missing.isEmpty &&
      selfComparison.newRows.isEmpty &&
      !selfComparison.hasRegression)

  expectError "schema version mismatch" "expected 1" <|
    parseSummaryArtifact (encoded.setObjVal! "schema_version" 2)
  expectError "time unit mismatch" "expected `nanoseconds`" <|
    parseSummaryArtifact (encoded.setObjVal! "time_unit" "microseconds")
  expectError "unknown top-level field" "not part of summary schema version 1" <|
    parseSummaryArtifact (encoded.setObjVal! "future_field" true)

  let rows := (encoded.getObjVal? "rows").toOption.get!.getArr?.toOption.get!
  let row := rows[0]!
  expectError "row integer type is checked" "$.rows[0].calls" <|
    parseSummaryArtifact (encoded.setObjVal! "rows" (.arr #[row.setObjVal! "calls" "one"]))
  let rowWithoutP95 :=
    match row with
    | .obj fields => .obj (fields.erase "p95_ns")
    | value => value
  expectError "missing row fields are rejected" "required field `p95_ns` is missing" <|
    parseSummaryArtifact (encoded.setObjVal! "rows" (.arr #[rowWithoutP95]))
  expectError "row keys must be unique" "duplicate summary key" <|
    parseSummaryArtifact (encoded.setObjVal! "rows" (.arr #[row, row]))
  expectError "event timing count must match" "event_timings has 0 entries" <|
    parseSummaryArtifact (encoded.setObjVal! "event_timings" (.arr #[]))
  expectError "retained event indices form an ordered prefix" "expected retained prefix index 0" <|
    parseSummaryArtifact <|
      setFirstArrayObjectField encoded "event_timings" "event_index" 7

  let badCalls :=
    row.setObjVal! "calls" 2
      |>.setObjVal! "total_ns" 500
      |>.setObjVal! "mean_ns" 250
  expectError "grouped calls reconcile with retained events" "call count sum 2" <|
    parseSummaryArtifact (encoded.setObjVal! "rows" (.arr #[badCalls]))
  let badTotal :=
    row.setObjVal! "total_ns" 251
      |>.setObjVal! "mean_ns" 251
      |>.setObjVal! "max_ns" 251
  expectError "grouped time reconciles with event timings" "total_ns sum 251" <|
    parseSummaryArtifact (encoded.setObjVal! "rows" (.arr #[badTotal]))
  expectError "grouped heartbeats reconcile with event timings" "total_heartbeats sum 32" <|
    parseSummaryArtifact <|
      setFirstArrayObjectField encoded "rows" "total_heartbeats" 32
  expectError "recorded thread total reconciles with event timings" "expected 250" <|
    parseSummaryArtifact (encoded.setObjVal! "recorded_thread_time_ns" 249)
  expectError "row share is recomputed exactly" "expected 1000" <|
    parseSummaryArtifact <|
      setFirstArrayObjectField encoded "rows" "share_permille" 999

  expectError "dropped events require a limit" "event_limit is null" <|
    parseSummaryArtifact (encoded.setObjVal! "event_limit" .null)
  expectError "truncated captures fill their retained limit" "retain exactly event_limit" <|
    parseSummaryArtifact (encoded.setObjVal! "event_limit" 2)
  let process := (encoded.getObjVal? "process_resources").toOption.get!
  expectError "peak RSS increase cannot exceed peak RSS" "exceeds peak resident set size" <|
    parseSummaryArtifact <|
      encoded.setObjVal! "process_resources"
        (process.setObjVal! "peak_resident_set_increase_kb" 4097)
  expectError "nonempty captures report at least one thread" "value from 1 through event_count" <|
    parseSummaryArtifact (encoded.setObjVal! "thread_count" 0)
  expectError "maximum depth is bounded by event count" "cannot be reached" <|
    parseSummaryArtifact (encoded.setObjVal! "max_depth" 1)

  let empty := summaryJson (analyze #[])
  expectError "empty captures report no threads" "empty capture must have zero threads" <|
    parseSummaryArtifact (empty.setObjVal! "thread_count" 1)

end LeanProfiler.Tests.Artifact
