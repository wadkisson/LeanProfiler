/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Artifact.Summary
import Std.Data.HashSet

/-!
# Summary consistency checks

These checks reconcile row totals, event timings, capture limits, and process measurements after
individual JSON fields have been decoded.
-/

namespace LeanProfiler.Internal.Artifact

/-- Reject a summary containing the same structured row key twice. -/
public def ensureUniqueRows (rows : Array SummaryRow) : Except String Unit := do
  let mut seen : Std.HashSet SummaryKey := {}
  for index in [:rows.size] do
    let key := rows[index]!.key
    if seen.contains key then
      throw s!"$.rows[{index}].key: duplicate summary key `{key.label}`"
    seen := seen.insert key

/-- Require retained event timings to form the ordered prefix `0, ..., n - 1`. -/
public def ensureTimingPrefix (timings : Array ArtifactEventTiming) : Except String Unit := do
  for index in [:timings.size] do
    let eventIndex := timings[index]!.eventIndex
    unless eventIndex == index do
      throw (s!"$.event_timings[{index}].event_index: expected retained prefix index {index}, "
        ++ s!"found {eventIndex}")

/--
Check cross-field invariants that cannot be established while decoding one value at a time.

The validator covers empty-capture metadata, event limits, process peaks, grouped call totals,
inclusive and exclusive timing totals, heartbeat totals, and each row's percentage.
-/
public def validateArtifact (artifact : SummaryArtifact) : Except String Unit := do
  if artifact.eventCount == 0 then
    unless artifact.threadCount == 0 do
      throw "$.thread_count: an empty capture must have zero threads"
    unless artifact.maxDepth == 0 do
      throw "$.max_depth: an empty capture must have depth zero"
    unless artifact.traceOriginNs == 0 do
      throw "$.trace_origin_ns: an empty capture must have origin zero"
    unless artifact.traceWindowNs == 0 do
      throw "$.trace_window_ns: an empty capture must have window zero"
  else
    unless 0 < artifact.threadCount && artifact.threadCount ≤ artifact.eventCount do
      throw (s!"$.thread_count: expected a value from 1 through event_count "
        ++ s!"({artifact.eventCount}), found {artifact.threadCount}")
    unless artifact.maxDepth < artifact.eventCount do
      throw (s!"$.max_depth: depth {artifact.maxDepth} cannot be reached by "
        ++ s!"{artifact.eventCount} retained event(s)")

  match artifact.eventLimit with
  | none =>
      unless artifact.droppedEvents == 0 do
        throw "$.dropped_events: spans cannot be dropped when event_limit is null"
  | some limit =>
      unless artifact.eventCount ≤ limit do
        throw s!"$.event_count: retained event count {artifact.eventCount} exceeds event_limit {limit}"
      if artifact.droppedEvents > 0 && artifact.eventCount != limit then
        throw (s!"$.dropped_events: a truncated capture must retain exactly event_limit "
          ++ s!"({limit}) events, found {artifact.eventCount}")

  if let some process := artifact.process then
    unless process.peakResidentSetIncreaseKb ≤ process.peakResidentSetSizeKb do
      throw (s!"$.process_resources.peak_resident_set_increase_kb: increase "
        ++ s!"{process.peakResidentSetIncreaseKb} exceeds peak resident set size "
        ++ s!"{process.peakResidentSetSizeKb}")

  let rowCalls := artifact.rows.foldl (init := 0) fun total row => total + row.calls
  unless rowCalls == artifact.eventCount do
    throw s!"$.rows: call count sum {rowCalls} does not match event_count {artifact.eventCount}"

  let timingTotalNs :=
    artifact.eventTimings.foldl (init := 0) fun total timing => total + timing.inclusiveNs
  let timingSelfNs :=
    artifact.eventTimings.foldl (init := 0) fun total timing => total + timing.selfNs
  let timingTotalHeartbeats :=
    artifact.eventTimings.foldl (init := 0) fun total timing =>
      total + timing.inclusiveHeartbeats
  let timingSelfHeartbeats :=
    artifact.eventTimings.foldl (init := 0) fun total timing =>
      total + timing.selfHeartbeats
  let rowTotalNs := artifact.rows.foldl (init := 0) fun total row => total + row.totalNs
  let rowSelfNs := artifact.rows.foldl (init := 0) fun total row => total + row.selfNs
  let rowTotalHeartbeats :=
    artifact.rows.foldl (init := 0) fun total row => total + row.totalHeartbeats
  let rowSelfHeartbeats :=
    artifact.rows.foldl (init := 0) fun total row => total + row.selfHeartbeats

  unless rowTotalNs == timingTotalNs do
    throw (s!"$.rows: total_ns sum {rowTotalNs} does not match event timing total "
      ++ s!"{timingTotalNs}")
  unless rowSelfNs == timingSelfNs do
    throw (s!"$.rows: self_ns sum {rowSelfNs} does not match event timing self total "
      ++ s!"{timingSelfNs}")
  unless rowTotalHeartbeats == timingTotalHeartbeats do
    throw (s!"$.rows: total_heartbeats sum {rowTotalHeartbeats} does not match event timing total "
      ++ s!"{timingTotalHeartbeats}")
  unless rowSelfHeartbeats == timingSelfHeartbeats do
    throw (s!"$.rows: self_heartbeats sum {rowSelfHeartbeats} does not match event timing self "
      ++ s!"total {timingSelfHeartbeats}")
  unless artifact.recordedThreadNs == timingSelfNs do
    throw (s!"$.recorded_thread_time_ns: found {artifact.recordedThreadNs}, expected "
      ++ s!"{timingSelfNs} from event self times")
  unless artifact.recordedHeartbeats == timingSelfHeartbeats do
    throw (s!"$.recorded_heartbeats: found {artifact.recordedHeartbeats}, expected "
      ++ s!"{timingSelfHeartbeats} from event self heartbeats")

  for index in [:artifact.rows.size] do
    let row := artifact.rows[index]!
    let expectedShare :=
      if artifact.recordedThreadNs == 0 then 0
      else (row.selfNs * 1000) / artifact.recordedThreadNs
    unless row.sharePermille == expectedShare do
      throw (s!"$.rows[{index}].share_permille: found {row.sharePermille}, expected "
        ++ s!"{expectedShare} from self_ns and recorded_thread_time_ns")

end LeanProfiler.Internal.Artifact
