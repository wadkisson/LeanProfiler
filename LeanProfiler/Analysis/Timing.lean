/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Analysis.Validation
public import Std.Data.HashMap.Basic

/-!
# Inclusive and exclusive timing

Exclusive measurements subtract the union of immediate, same-thread child intervals. Cross-thread
children remain correlated through their parent index but do not reduce a parent's host-thread time.
-/

namespace LeanProfiler
namespace Internal

/-- Immediate same-thread child intervals and their subtractable heartbeats. -/
public structure ChildMetrics where
  intervals : Array Interval := #[]
  heartbeats : Nat := 0

/--
Collect immediate same-thread children for every parent.

Malformed child intervals are clipped to the parent. Heartbeats are subtracted only when the full
child interval lies inside its parent, keeping the diagnostic report internally bounded.
-/
public def childMetrics (events : Array Event) : Std.HashMap Nat ChildMetrics := Id.run do
  let mut byIndex : Std.HashMap Nat Event := {}
  for event in events do
    if !byIndex.contains event.index then
      byIndex := byIndex.insert event.index event
  let mut result : Std.HashMap Nat ChildMetrics := {}
  for event in events do
    match event.parentIndex with
    | none => pure ()
    | some parent =>
        match byIndex[parent]? with
        | some parentEvent =>
            if parentEvent.threadId == event.threadId then
              let current := result.getD parent {}
              let childStart := max parentEvent.startNs event.startNs
              let childEnd := min parentEvent.endNs event.endNs
              result := result.insert parent {
                intervals := current.intervals.push {
                  startNs := childStart
                  endNs := childEnd
                  eventIndex := event.index
                }
                heartbeats :=
                  if parentEvent.startNs ≤ event.startNs && event.endNs ≤ parentEvent.endNs then
                    current.heartbeats + event.heartbeats
                  else
                    current.heartbeats
              }
        | none => pure ()
  return result

/-- Compute one event's inclusive and child-subtracted measurements. -/
public def timingForEvent
    (children : Std.HashMap Nat ChildMetrics) (event : Event) : EventTiming :=
  let inclusiveNs := event.durationNs
  let child := children.getD event.index {}
  let childNs := coveredDuration child.intervals
  {
    event
    inclusiveNs
    selfNs := inclusiveNs - min inclusiveNs childNs
    inclusiveHeartbeats := event.heartbeats
    selfHeartbeats := event.heartbeats - min event.heartbeats child.heartbeats
  }

/-- Child subtraction cannot make an exclusive measurement exceed its inclusive measurement. -/
public theorem timingForEvent_isConsistent
    (children : Std.HashMap Nat ChildMetrics) (event : Event) :
    (timingForEvent children event).IsConsistent := by
  simp [timingForEvent, EventTiming.IsConsistent]

end Internal
end LeanProfiler
