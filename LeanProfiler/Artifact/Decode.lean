/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Artifact.Summary
public import Lean.Data.Json

/-!
# Summary field decoding

The decoder accepts exactly the fields and integer forms written by summary schema version 1.
Path-aware errors point to the value that failed.
-/

namespace LeanProfiler
namespace Internal.Artifact

open Lean

/-- Prefix a decoder error with the JSON path currently being read. -/
public def withPath (path : String) (result : Except String α) : Except String α :=
  match result with
  | .ok value => .ok value
  | .error message => .error s!"{path}: {message}"

/-- Require exactly the fields listed for one schema-version-1 object. -/
public def expectFields (path : String) (expected : List String) (json : Json) :
    Except String Unit := do
  let object ← withPath path json.getObj?
  let actual := object.foldl (init := []) fun fields key _ => key :: fields
  for key in expected do
    unless actual.contains key do
      throw s!"{path}: required field `{key}` is missing"
  for key in actual do
    unless expected.contains key do
      throw s!"{path}: field `{key}` is not part of summary schema version 1"

/-- Read one required object field and attach its path to any error. -/
public def field (path key : String) (json : Json) : Except String Json :=
  withPath s!"{path}.{key}" (json.getObjVal? key)

/-- Read a required natural-number field without numeric coercion. -/
public def natField (path key : String) (json : Json) : Except String Nat := do
  let value ← field path key json
  withPath s!"{path}.{key}" value.getNat?

/-- Read a required integer field without numeric coercion. -/
public def intField (path key : String) (json : Json) : Except String Int := do
  let value ← field path key json
  withPath s!"{path}.{key}" value.getInt?

/-- Read a required string field. -/
public def stringField (path key : String) (json : Json) : Except String String := do
  let value ← field path key json
  withPath s!"{path}.{key}" value.getStr?

/-- Read a nullable natural-number field. -/
public def optionNatField
    (path key : String) (json : Json) : Except String (Option Nat) := do
  let value ← field path key json
  match value with
  | .null => pure none
  | value => some <$> withPath s!"{path}.{key}" value.getNat?

/-- Read a nullable string field. -/
public def optionStringField
    (path key : String) (json : Json) : Except String (Option String) := do
  let value ← field path key json
  match value with
  | .null => pure none
  | value => some <$> withPath s!"{path}.{key}" value.getStr?

/-- Decode an array while including each item index in errors. -/
public def parseArray (path : String) (json : Json)
    (parseItem : String → Json → Except String α) : Except String (Array α) := do
  let items ← withPath path json.getArr?
  let mut result := #[]
  for index in [:items.size] do
    result := result.push (← parseItem s!"{path}[{index}]" items[index]!)
  pure result

/-- Decode the complete structured key of a summary row. -/
public def parseSummaryKey (path : String) (json : Json) : Except String SummaryKey := do
  expectFields path
    ["name", "phase", "activity", "backend", "dtype", "device", "module"] json
  pure {
    name := ← stringField path "name" json
    phase := ← optionStringField path "phase" json
    activity := ← optionStringField path "activity" json
    backend := ← optionStringField path "backend" json
    dtype := ← optionStringField path "dtype" json
    device := ← optionStringField path "device" json
    moduleName := ← optionStringField path "module" json
  }

/-- Decode one grouped row and check its local statistical invariants. -/
public def parseSummaryRow (path : String) (json : Json) : Except String SummaryRow := do
  expectFields path [
    "key", "calls", "self_ns", "total_ns", "self_heartbeats", "total_heartbeats", "min_ns",
    "mean_ns", "median_ns", "p95_ns", "max_ns", "share_permille", "alloc_bytes",
    "peak_live_bytes", "alloc_delta_bytes"
  ] json
  let row : SummaryRow := {
    key := ← parseSummaryKey s!"{path}.key" (← field path "key" json)
    calls := ← natField path "calls" json
    selfNs := ← natField path "self_ns" json
    totalNs := ← natField path "total_ns" json
    selfHeartbeats := ← natField path "self_heartbeats" json
    totalHeartbeats := ← natField path "total_heartbeats" json
    minNs := ← natField path "min_ns" json
    meanNs := ← natField path "mean_ns" json
    medianNs := ← natField path "median_ns" json
    p95Ns := ← natField path "p95_ns" json
    maxNs := ← natField path "max_ns" json
    sharePermille := ← natField path "share_permille" json
    allocBytes := ← natField path "alloc_bytes" json
    peakLiveBytes := ← natField path "peak_live_bytes" json
    allocDeltaBytes := ← intField path "alloc_delta_bytes" json
  }
  if row.calls == 0 then
    throw s!"{path}.calls: grouped rows must contain at least one call"
  if row.selfNs > row.totalNs then
    throw s!"{path}: self_ns exceeds total_ns"
  if row.selfHeartbeats > row.totalHeartbeats then
    throw s!"{path}: self_heartbeats exceeds total_heartbeats"
  unless row.minNs ≤ row.meanNs && row.meanNs ≤ row.maxNs do
    throw s!"{path}: mean_ns lies outside min_ns and max_ns"
  unless row.minNs ≤ row.medianNs && row.medianNs ≤ row.p95Ns && row.p95Ns ≤ row.maxNs do
    throw s!"{path}: percentile fields are not ordered"
  unless row.meanNs == row.totalNs / row.calls do
    throw s!"{path}.mean_ns: expected floor(total_ns / calls)"
  if row.sharePermille > 1000 then
    throw s!"{path}.share_permille: value exceeds 1000"
  pure row

/-- Decode one analyzer validation issue. -/
public def parseIssue (path : String) (json : Json) : Except String ValidationIssue := do
  expectFields path ["event_index", "message"] json
  pure {
    eventIndex := ← optionNatField path "event_index" json
    message := ← stringField path "message" json
  }

/-- Decode one retained event timing and check exclusive bounds. -/
public def parseEventTiming
    (path : String) (json : Json) : Except String ArtifactEventTiming := do
  expectFields path [
    "event_index", "inclusive_ns", "self_ns", "inclusive_heartbeats", "self_heartbeats"
  ] json
  let timing : ArtifactEventTiming := {
    eventIndex := ← natField path "event_index" json
    inclusiveNs := ← natField path "inclusive_ns" json
    selfNs := ← natField path "self_ns" json
    inclusiveHeartbeats := ← natField path "inclusive_heartbeats" json
    selfHeartbeats := ← natField path "self_heartbeats" json
  }
  if timing.selfNs > timing.inclusiveNs then
    throw s!"{path}: self_ns exceeds inclusive_ns"
  if timing.selfHeartbeats > timing.inclusiveHeartbeats then
    throw s!"{path}: self_heartbeats exceeds inclusive_heartbeats"
  pure timing

/-- Decode the whole-process measurements stored with a capture. -/
public def parseProcessMetrics
    (path : String) (json : Json) : Except String ProcessMetrics := do
  expectFields path [
    "user_cpu_ms", "system_cpu_ms", "peak_resident_set_size_kb",
    "peak_resident_set_increase_kb", "minor_page_faults", "major_page_faults",
    "block_input_ops", "block_output_ops", "voluntary_context_switches",
    "involuntary_context_switches"
  ] json
  pure {
    userCpuMs := ← natField path "user_cpu_ms" json
    systemCpuMs := ← natField path "system_cpu_ms" json
    peakResidentSetSizeKb := ← natField path "peak_resident_set_size_kb" json
    peakResidentSetIncreaseKb := ← natField path "peak_resident_set_increase_kb" json
    minorPageFaults := ← natField path "minor_page_faults" json
    majorPageFaults := ← natField path "major_page_faults" json
    blockInputOps := ← natField path "block_input_ops" json
    blockOutputOps := ← natField path "block_output_ops" json
    voluntaryContextSwitches := ← natField path "voluntary_context_switches" json
    involuntaryContextSwitches := ← natField path "involuntary_context_switches" json
  }

/-- Decode a nullable process-measurement object. -/
public def parseOptionalProcessMetrics
    (path : String) (json : Json) : Except String (Option ProcessMetrics) :=
  match json with
  | .null => pure none
  | json => some <$> parseProcessMetrics path json

end LeanProfiler.Internal.Artifact
