/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Analysis.Report
public import Lean.Data.Json
import LeanProfiler.Internal.Json

/-!
# Summary JSON

The versioned summary keeps integer nanosecond measurements, grouped rows, validation findings, and
the per-event inclusive/exclusive values needed for strict consistency checks.
-/

namespace LeanProfiler
namespace Internal

def processMetricsJson (metrics : ProcessMetrics) : Lean.Json :=
  Lean.Json.mkObj [
    ("user_cpu_ms", Internal.Json.nat metrics.userCpuMs),
    ("system_cpu_ms", Internal.Json.nat metrics.systemCpuMs),
    ("peak_resident_set_size_kb", Internal.Json.nat metrics.peakResidentSetSizeKb),
    ("peak_resident_set_increase_kb", Internal.Json.nat metrics.peakResidentSetIncreaseKb),
    ("minor_page_faults", Internal.Json.nat metrics.minorPageFaults),
    ("major_page_faults", Internal.Json.nat metrics.majorPageFaults),
    ("block_input_ops", Internal.Json.nat metrics.blockInputOps),
    ("block_output_ops", Internal.Json.nat metrics.blockOutputOps),
    ("voluntary_context_switches", Internal.Json.nat metrics.voluntaryContextSwitches),
    ("involuntary_context_switches", Internal.Json.nat metrics.involuntaryContextSwitches)
  ]

def issueJson (problem : ValidationIssue) : Lean.Json :=
  Lean.Json.mkObj [
    ("event_index", Internal.Json.option Internal.Json.nat problem.eventIndex),
    ("message", .str problem.message)
  ]

def rowJson (row : SummaryRow) : Lean.Json :=
  Lean.Json.mkObj [
    ("key", Internal.Json.summaryKey row.key),
    ("calls", Internal.Json.nat row.calls),
    ("self_ns", Internal.Json.nat row.selfNs),
    ("total_ns", Internal.Json.nat row.totalNs),
    ("self_heartbeats", Internal.Json.nat row.selfHeartbeats),
    ("total_heartbeats", Internal.Json.nat row.totalHeartbeats),
    ("min_ns", Internal.Json.nat row.minNs),
    ("mean_ns", Internal.Json.nat row.meanNs),
    ("median_ns", Internal.Json.nat row.medianNs),
    ("p95_ns", Internal.Json.nat row.p95Ns),
    ("max_ns", Internal.Json.nat row.maxNs),
    ("share_permille", Internal.Json.nat row.sharePermille),
    ("alloc_bytes", Internal.Json.nat row.allocBytes),
    ("peak_live_bytes", Internal.Json.nat row.peakLiveBytes),
    ("alloc_delta_bytes", Internal.Json.int row.allocDeltaBytes)
  ]

/-- Per-event inclusive and exclusive measurements retained in the summary artifact. -/
def timingJson (timing : EventTiming) : Lean.Json :=
  Lean.Json.mkObj [
    ("event_index", Internal.Json.nat timing.event.index),
    ("inclusive_ns", Internal.Json.nat timing.inclusiveNs),
    ("self_ns", Internal.Json.nat timing.selfNs),
    ("inclusive_heartbeats", Internal.Json.nat timing.inclusiveHeartbeats),
    ("self_heartbeats", Internal.Json.nat timing.selfHeartbeats)
  ]

end Internal

/-- Stable machine-readable summary. Every duration field is an integer nanosecond count. -/
public def summaryJson (report : Report) : Lean.Json :=
  Lean.Json.mkObj [
    ("schema_version", Internal.Json.nat 1),
    ("clock", .str "monotonic"),
    ("time_unit", .str "nanoseconds"),
    ("event_count", Internal.Json.nat report.events.size),
    ("thread_count", Internal.Json.nat report.threadCount),
    ("max_depth", Internal.Json.nat report.maxDepth),
    ("trace_origin_ns", Internal.Json.nat report.traceOriginNs),
    ("trace_window_ns", Internal.Json.nat report.traceWindowNs),
    ("recorded_thread_time_ns", Internal.Json.nat report.recordedThreadNs),
    ("recorded_heartbeats", Internal.Json.nat report.recordedHeartbeats),
    ("event_limit", Internal.Json.option Internal.Json.nat report.eventLimit),
    ("dropped_events", Internal.Json.nat report.droppedEvents),
    ("process_resources", Internal.Json.option Internal.processMetricsJson report.process),
    ("validation_issues", .arr <| report.issues.map Internal.issueJson),
    ("event_timings", .arr <| report.timings.map Internal.timingJson),
    ("rows", .arr <| report.rows.map Internal.rowJson)
  ]

end LeanProfiler
