/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Artifact.Summary
public import Lean.Data.Json
import LeanProfiler.Artifact.Decode
import LeanProfiler.Artifact.Validation

/-!
# Reading summary artifacts

The top-level decoder checks the schema marker and fixed units before assembling and validating the
artifact. File errors include the input path.
-/

namespace LeanProfiler

open Lean
open Internal.Artifact

/--
Decode a version-1 summary.

Every field emitted by `summaryJson` is required, unknown fields are rejected, and numeric values
must be JSON integers. This keeps comparisons from accepting a partially compatible artifact.
-/
public def parseSummaryArtifact (json : Json) : Except String SummaryArtifact := do
  expectFields "$" [
    "schema_version", "clock", "time_unit", "event_count", "thread_count", "max_depth",
    "trace_origin_ns", "trace_window_ns", "recorded_thread_time_ns", "recorded_heartbeats",
    "event_limit", "dropped_events", "process_resources", "validation_issues", "event_timings",
    "rows"
  ] json
  let schemaVersion ← natField "$" "schema_version" json
  unless schemaVersion == 1 do
    throw s!"$.schema_version: expected 1, found {schemaVersion}"
  let clock ← stringField "$" "clock" json
  unless clock == "monotonic" do
    throw s!"$.clock: expected `monotonic`, found `{clock}`"
  let timeUnit ← stringField "$" "time_unit" json
  unless timeUnit == "nanoseconds" do
    throw s!"$.time_unit: expected `nanoseconds`, found `{timeUnit}`"
  let eventCount ← natField "$" "event_count" json
  let eventTimings ←
    parseArray "$.event_timings" (← field "$" "event_timings" json) parseEventTiming
  unless eventCount == eventTimings.size do
    throw s!"$.event_count: found {eventCount}, but event_timings has {eventTimings.size} entries"
  ensureTimingPrefix eventTimings
  let rows ← parseArray "$.rows" (← field "$" "rows" json) parseSummaryRow
  ensureUniqueRows rows
  let eventLimit ← optionNatField "$" "event_limit" json
  let processJson ← field "$" "process_resources" json
  let artifact : SummaryArtifact := {
    eventCount
    threadCount := ← natField "$" "thread_count" json
    maxDepth := ← natField "$" "max_depth" json
    traceOriginNs := ← natField "$" "trace_origin_ns" json
    traceWindowNs := ← natField "$" "trace_window_ns" json
    recordedThreadNs := ← natField "$" "recorded_thread_time_ns" json
    recordedHeartbeats := ← natField "$" "recorded_heartbeats" json
    eventLimit
    droppedEvents := ← natField "$" "dropped_events" json
    process := ← parseOptionalProcessMetrics "$.process_resources" processJson
    issues := ← parseArray "$.validation_issues"
      (← field "$" "validation_issues" json) parseIssue
    eventTimings
    rows
  }
  validateArtifact artifact
  pure artifact

/-- Read and decode one summary file, including its path in parser errors. -/
public def readSummaryArtifact (path : System.FilePath) : IO SummaryArtifact := do
  let contents ← IO.FS.readFile path
  let json ←
    match Json.parse contents with
    | .ok json => pure json
    | .error message =>
        throw <| IO.userError s!"{path}: invalid JSON: {message}"
  match parseSummaryArtifact json with
  | .ok artifact => pure artifact
  | .error message =>
      throw <| IO.userError s!"{path}: invalid LeanProfiler summary: {message}"

end LeanProfiler
