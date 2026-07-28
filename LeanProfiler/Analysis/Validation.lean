/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Analysis.Report
import Std.Data.HashMap

/-!
# Event validation

The validator checks the event forest before grouped statistics are trusted. Interval union also
protects exclusive-time calculation from malformed or overlapping children.
-/

namespace LeanProfiler
namespace Internal

/-- Half-open event interval used by validation and child subtraction. -/
public structure Interval where
  startNs : Nat
  endNs : Nat
  eventIndex : Nat
  deriving Inhabited

/-- Order intervals by start time, then by end time. -/
public def intervalLt (a b : Interval) : Bool :=
  a.startNs < b.startNs || (a.startNs == b.startNs && a.endNs < b.endNs)

/-- Length of the union of half-open intervals. Reversed and empty intervals contribute zero. -/
public def coveredDuration (intervals : Array Interval) : Nat := Id.run do
  let sorted := (intervals.filter fun interval => interval.startNs < interval.endNs).qsort intervalLt
  if sorted.isEmpty then
    return 0
  else
    let first := sorted[0]!
    let mut currentStart := first.startNs
    let mut currentEnd := first.endNs
    let mut total := 0
    for interval in sorted[1:] do
      if interval.startNs ≤ currentEnd then
        currentEnd := max currentEnd interval.endNs
      else
        total := total + (currentEnd - currentStart)
        currentStart := interval.startNs
        currentEnd := interval.endNs
    return total + (currentEnd - currentStart)

def issue (index : Option Nat) (message : String) : ValidationIssue :=
  { eventIndex := index, message }

end Internal

/-- Check indices, parent links, depths, threads, and interval containment. -/
public def validateEvents (events : Array Event) : Array ValidationIssue := Id.run do
  let mut issues : Array ValidationIssue := #[]
  let mut byIndex : Std.HashMap Nat Event := {}
  for event in events do
    if event.endNs < event.startNs then
      issues := issues.push <| Internal.issue (some event.index)
        s!"end time {event.endNs} precedes start time {event.startNs}"
    if byIndex.contains event.index then
      issues := issues.push <| Internal.issue (some event.index) "duplicate event index"
    else
      byIndex := byIndex.insert event.index event
  for event in events do
    match event.parentIndex with
    | none =>
        if event.depth != 0 then
          issues := issues.push <| Internal.issue (some event.index)
            s!"root event has depth {event.depth}, expected 0"
    | some parentIndex =>
        match byIndex[parentIndex]? with
        | none =>
            issues := issues.push <| Internal.issue (some event.index)
              s!"parent event {parentIndex} is missing"
        | some parent =>
            if parentIndex ≥ event.index then
              issues := issues.push <| Internal.issue (some event.index)
                s!"parent index {parentIndex} is not earlier than child index {event.index}"
            if event.depth != parent.depth + 1 then
              issues := issues.push <| Internal.issue (some event.index)
                s!"depth {event.depth} does not follow parent depth {parent.depth}"
            if event.threadId == parent.threadId &&
                (event.startNs < parent.startNs || event.endNs > parent.endNs) then
              issues := issues.push <| Internal.issue (some event.index)
                (s!"interval [{event.startNs}, {event.endNs}] lies outside parent interval "
                  ++ s!"[{parent.startNs}, {parent.endNs}]")
  -- Roots are siblings under an implicit thread-local parent. Include them in the same overlap
  -- check so malformed captures cannot double-count overlapping root time without a diagnostic.
  let mut siblingsByParent : Std.HashMap (Option Nat × UInt64) (Array Internal.Interval) := {}
  for event in events do
    let key := (event.parentIndex, event.threadId)
    let siblings := siblingsByParent.getD key #[]
    siblingsByParent := siblingsByParent.insert key (siblings.push {
      startNs := event.startNs
      endNs := event.endNs
      eventIndex := event.index
    })
  for (_, siblings) in siblingsByParent do
    let sorted :=
      (siblings.filter fun interval => interval.startNs < interval.endNs).qsort Internal.intervalLt
    if let some first := sorted[0]? then
      let mut previousEnd := first.endNs
      for interval in sorted[1:] do
        if interval.startNs < previousEnd then
          issues := issues.push <| Internal.issue (some interval.eventIndex)
            "immediate sibling spans overlap on one thread"
        previousEnd := max previousEnd interval.endNs
  return issues

end LeanProfiler
