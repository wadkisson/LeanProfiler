/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Analysis.Timing
import Std.Data.HashMap
import Std.Data.HashSet

/-!
# Capture summaries

Repeated events are grouped by their structured keys and ordered deterministically. The analyzer
also records the trace window, thread count, total exclusive work, and validation problems.
-/

namespace LeanProfiler
namespace Internal

/--
Return the nearest-rank percentile of an ascending array.

The rank is one-based and rounded upward. Empty input and a zero denominator return zero.
-/
public def percentileNearestRank
    (sorted : Array Nat) (numerator denominator : Nat) : Nat :=
  if sorted.isEmpty || denominator == 0 then
    0
  else
    let rank := max 1 ((numerator * sorted.size + denominator - 1) / denominator)
    sorted[min (rank - 1) (sorted.size - 1)]!

/-- Mutable totals collected while events are grouped by summary key. -/
public structure RowAccumulator where
  totalNs : Nat := 0
  selfNs : Nat := 0
  totalHeartbeats : Nat := 0
  selfHeartbeats : Nat := 0
  durations : Array Nat := #[]
  allocBytes : Nat := 0
  peakLiveBytes : Nat := 0
  allocDeltaBytes : Int := 0

/--
Group event timings by complete summary key.

Durations and counters are aggregated per key, p95 uses nearest rank, and the final rows are sorted
by descending self time with the structured key as a stable tie-breaker.
-/
public def buildRows (timings : Array EventTiming) (recordedThreadNs : Nat) :
    Array SummaryRow := Id.run do
  let mut totals : Std.HashMap SummaryKey RowAccumulator := {}
  for timing in timings do
    let key := timing.event.summaryKey
    let current := totals.getD key {}
    let metadata := timing.event.metadata
    let peak := max (metadata.allocPeakBytes.getD 0) (metadata.allocLiveBytes.getD 0)
    totals := totals.insert key {
      totalNs := current.totalNs + timing.inclusiveNs
      selfNs := current.selfNs + timing.selfNs
      totalHeartbeats := current.totalHeartbeats + timing.inclusiveHeartbeats
      selfHeartbeats := current.selfHeartbeats + timing.selfHeartbeats
      durations := current.durations.push timing.inclusiveNs
      allocBytes := current.allocBytes + metadata.allocBytes.getD 0
      peakLiveBytes := max current.peakLiveBytes peak
      allocDeltaBytes := current.allocDeltaBytes + metadata.allocDeltaBytes.getD 0
    }
  let rows := totals.toArray.map fun (key, acc) =>
    let durations := acc.durations.qsort (· < ·)
    let calls := durations.size
    {
      key
      totalNs := acc.totalNs
      selfNs := acc.selfNs
      totalHeartbeats := acc.totalHeartbeats
      selfHeartbeats := acc.selfHeartbeats
      calls
      minNs := durations[0]?.getD 0
      meanNs := if calls == 0 then 0 else acc.totalNs / calls
      medianNs := percentileNearestRank durations 1 2
      p95Ns := percentileNearestRank durations 95 100
      maxNs := durations.back?.getD 0
      sharePermille :=
        if recordedThreadNs == 0 then 0 else (acc.selfNs * 1000) / recordedThreadNs
      allocBytes := acc.allocBytes
      peakLiveBytes := acc.peakLiveBytes
      allocDeltaBytes := acc.allocDeltaBytes
    }
  return rows.qsort fun a b =>
    a.selfNs > b.selfNs ||
      (a.selfNs == b.selfNs && a.key.lt b.key)

end Internal

/-- Validate and summarize a capture. -/
public def analyze (events : Array Event) : Report := Id.run do
  let events := events.qsort (fun a b => a.index < b.index)
  let children := Internal.childMetrics events
  let timings := events.map (Internal.timingForEvent children)
  let recordedThreadNs := timings.foldl (init := 0) (fun total timing => total + timing.selfNs)
  let recordedHeartbeats :=
    timings.foldl (init := 0) (fun total timing => total + timing.selfHeartbeats)
  let (origin, endNs) :=
    match events[0]? with
    | none => (0, 0)
    | some first =>
        events.foldl
          (init := (first.startNs, first.endNs))
          (fun (lo, hi) event => (min lo event.startNs, max hi event.endNs))
  let mut threads : Std.HashSet UInt64 := {}
  let mut maxDepth := 0
  for event in events do
    threads := threads.insert event.threadId
    maxDepth := max maxDepth event.depth
  return {
    events
    timings
    rows := Internal.buildRows timings recordedThreadNs
    issues := validateEvents events
    traceOriginNs := origin
    traceWindowNs := endNs - origin
    recordedThreadNs
    recordedHeartbeats
    threadCount := threads.size
    maxDepth
  }

/-- Every timing emitted by `analyze` obeys the inclusive/exclusive measurement bounds. -/
public theorem analyze_timings_areConsistent (events : Array Event) :
    ∀ timing ∈ (analyze events).timings, timing.IsConsistent := by
  intro timing hTiming
  simp only [analyze] at hTiming
  obtain ⟨event, _, rfl⟩ := Array.mem_map.mp hTiming
  exact Internal.timingForEvent_isConsistent _ event

end LeanProfiler
