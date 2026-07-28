/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Runtime.Process

/-!
# Analysis results

These types describe validation problems, per-event timing, grouped rows, and complete reports.
-/

namespace LeanProfiler

/-- One structural problem found in a captured event forest. -/
public structure ValidationIssue where
  eventIndex : Option Nat
  message : String
  deriving Repr, Inhabited, DecidableEq

/-- Inclusive and exclusive time for one event. -/
public structure EventTiming where
  event : Event
  inclusiveNs : Nat
  selfNs : Nat
  inclusiveHeartbeats : Nat
  selfHeartbeats : Nat
  deriving Repr, Inhabited

/--
The exclusive measurements of an event timing are bounded by its inclusive measurements.

`analyze` establishes this invariant.
-/
@[expose] public def EventTiming.IsConsistent (timing : EventTiming) : Prop :=
  timing.selfNs ≤ timing.inclusiveNs ∧
    timing.selfHeartbeats ≤ timing.inclusiveHeartbeats

/-- Dimensions that identify one grouped summary row. -/
public structure SummaryKey where
  name : String
  phase : Option String := none
  activity : Option String := none
  backend : Option String := none
  dtype : Option String := none
  device : Option String := none
  moduleName : Option String := none
  deriving Repr, Inhabited, BEq, Hashable

/-- Grouping key for one event. Shapes and step numbers remain per-event trace arguments. -/
public def Event.summaryKey (event : Event) : SummaryKey :=
  {
    name := event.name
    phase := event.metadata.phase
    activity := event.metadata.activity
    backend := event.metadata.backend
    dtype := event.metadata.dtype
    device := event.metadata.device
    moduleName := event.metadata.moduleName
  }

/-- Human-readable display label for a grouped row. -/
public def SummaryKey.label (key : SummaryKey) : String :=
  let labels := [
    key.phase.map (fun value => s!"phase={value}"),
    key.activity.map (fun value => s!"activity={value}"),
    key.backend.map (fun value => s!"backend={value}"),
    key.dtype.map (fun value => s!"dtype={value}"),
    key.device.map (fun value => s!"device={value}"),
    key.moduleName.map (fun value => s!"module={value}")
  ].filterMap id
  if labels.isEmpty then key.name else s!"{key.name} [{String.intercalate ", " labels}]"

/--
Compare complete grouping keys lexicographically.

This compares the structured fields directly rather than depending on their display labels. Every
field that participates in grouping is included.
-/
public def SummaryKey.compareLex (left right : SummaryKey) : Ordering :=
  (Ord.compare left.name right.name).then <|
    (Ord.compare left.phase right.phase).then <|
      (Ord.compare left.activity right.activity).then <|
        (Ord.compare left.backend right.backend).then <|
          (Ord.compare left.dtype right.dtype).then <|
            (Ord.compare left.device right.device).then <|
              Ord.compare left.moduleName right.moduleName

/-- Strict ordering used for deterministic report and comparison output. -/
public def SummaryKey.lt (left right : SummaryKey) : Bool :=
  left.compareLex right == .lt

/-- Comparing a grouping key with itself yields equality. -/
public theorem SummaryKey.compareLex_self (key : SummaryKey) : key.compareLex key = .eq := by
  simp [SummaryKey.compareLex]

/-- Complete grouping keys compare equal exactly when all of their fields are equal. -/
public theorem SummaryKey.compareLex_eq_eq_iff (left right : SummaryKey) :
    left.compareLex right = .eq ↔ left = right := by
  cases left
  cases right
  simp [SummaryKey.compareLex]

/-- Statistics for events sharing a structured summary key. -/
public structure SummaryRow where
  key : SummaryKey
  totalNs : Nat
  selfNs : Nat
  totalHeartbeats : Nat
  selfHeartbeats : Nat
  calls : Nat
  minNs : Nat
  meanNs : Nat
  medianNs : Nat
  p95Ns : Nat
  maxNs : Nat
  sharePermille : Nat
  allocBytes : Nat
  peakLiveBytes : Nat
  allocDeltaBytes : Int
  deriving Repr, Inhabited

/--
Analyzed capture.

`recordedThreadNs` is the sum of all event self-times. In a structurally valid capture this
telescopes to the thread-local root durations, including worker roots linked to a logical parent on
another thread. Concurrent threads can overlap, so it is intentionally not called wall time.
`traceWindowNs` is the interval from the earliest start to the latest end.
-/
public structure Report where
  events : Array Event
  timings : Array EventTiming
  rows : Array SummaryRow
  issues : Array ValidationIssue
  traceOriginNs : Nat
  traceWindowNs : Nat
  recordedThreadNs : Nat
  recordedHeartbeats : Nat
  threadCount : Nat
  maxDepth : Nat
  process : Option ProcessMetrics := none
  eventLimit : Option Nat := none
  droppedEvents : Nat := 0
  deriving Repr, Inhabited

end LeanProfiler
