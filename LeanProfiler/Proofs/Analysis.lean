/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Analysis

/-!
# Analysis invariants

Bounds between exclusive and inclusive time and heartbeat measurements.
-/

namespace LeanProfiler

/-- A consistent event timing has no more exclusive time than inclusive time. -/
public theorem EventTiming.selfNs_le_inclusiveNs
    (timing : EventTiming) (hTiming : timing.IsConsistent) :
    timing.selfNs ≤ timing.inclusiveNs :=
  hTiming.1

/-- A consistent event timing has no more exclusive heartbeats than inclusive heartbeats. -/
public theorem EventTiming.selfHeartbeats_le_inclusiveHeartbeats
    (timing : EventTiming) (hTiming : timing.IsConsistent) :
    timing.selfHeartbeats ≤ timing.inclusiveHeartbeats :=
  hTiming.2

/-- A timing selected from an analyzed report has bounded exclusive time. -/
public theorem selfNs_le_inclusiveNs_of_mem_analyze
    (events : Array Event) (timing : EventTiming)
    (hTiming : timing ∈ (analyze events).timings) :
    timing.selfNs ≤ timing.inclusiveNs :=
  timing.selfNs_le_inclusiveNs <| analyze_timings_areConsistent events timing hTiming

/-- A timing selected from an analyzed report has bounded exclusive heartbeats. -/
public theorem selfHeartbeats_le_inclusiveHeartbeats_of_mem_analyze
    (events : Array Event) (timing : EventTiming)
    (hTiming : timing ∈ (analyze events).timings) :
    timing.selfHeartbeats ≤ timing.inclusiveHeartbeats :=
  timing.selfHeartbeats_le_inclusiveHeartbeats <|
    analyze_timings_areConsistent events timing hTiming

end LeanProfiler
