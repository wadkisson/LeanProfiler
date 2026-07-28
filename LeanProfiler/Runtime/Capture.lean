/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Runtime.Process
public import Std.Data.HashMap.Basic
public import Std.Sync.Mutex

/-!
# Capture state and context

This module owns the process-wide event buffer. Application code normally reaches it through
`span`, `profile`, and the dynamic metadata helpers.
-/

namespace LeanProfiler

namespace Internal

/-- Session limits and whole-process measurements returned with a capture. -/
public structure CaptureStatus where
  process : Option ProcessMetrics
  eventLimit : Option Nat
  droppedEvents : Nat
  deriving Repr, Inhabited, DecidableEq

/--
Mutable state for the process-wide capture.

`nextIndex` never moves backwards during a capture. Each live reservation appears in its thread
stack and in `eventDepths`; completed retained events appear in `events`. `reportClaimed` prevents
two callers from exporting the same capture.
-/
public structure ProfilerState where
  events : Array Event := #[]
  reportClaimed : Bool := false
  nextIndex : Nat := 0
  eventLimit : Option Nat := none
  droppedEvents : Nat := 0
  processStart : Option ProcessSnapshot := none
  stacks : Std.HashMap UInt64 (Array Nat) := {}
  contexts : Std.HashMap UInt64 (Metadata × Option Nat) := {}
  eventDepths : Std.HashMap Nat Nat := {}
  deriving Inhabited

/-- Shared capture state serialized by a mutex. -/
public initialize profilerState : Std.Mutex ProfilerState ← Std.Mutex.new {}

/-- Process identifier sampled once because it cannot change during a run. -/
public initialize processId : UInt32 ← IO.Process.getPID

/-- Information fixed when a span is admitted to the capture. -/
public structure SpanReservation where
  depth : Nat
  index : Nat
  parentIndex : Option Nat
  threadId : UInt64
  metadata : Metadata

/-- Reserve an index and push it onto the current thread's nesting stack. -/
public def reserveSpan : IO SpanReservation := do
  let threadId ← IO.getTID
  profilerState.atomically do
    let state ← get
    let stack := state.stacks.getD threadId #[]
    let (metadata, explicitParent) := state.contexts.getD threadId ({}, none)
    -- A logical cross-thread parent seeds the local stack. Once a local span is active, ordinary
    -- nesting wins so descendants do not become overlapping siblings.
    let parentIndex := stack.back? <|> explicitParent
    let depth :=
      match parentIndex with
      | some parent => state.eventDepths.getD parent stack.size + 1
      | none => stack.size
    let reservation := {
      depth
      index := state.nextIndex
      parentIndex
      threadId
      metadata
    }
    set {
      state with
      nextIndex := state.nextIndex + 1
      stacks := state.stacks.insert threadId (stack.push reservation.index)
      eventDepths := state.eventDepths.insert reservation.index reservation.depth
    }
    pure reservation

/-- Store a completed event and remove its reservation from the current thread's stack. -/
public def completeSpan (event : Event) : IO Unit := do
  profilerState.atomically do
    let state ← get
    let stack := state.stacks.getD event.threadId #[]
    let stack :=
      match stack.back? with
      | some top =>
          if top == event.index then stack.pop
          else stack.filter (fun index => index != event.index)
      | none => stack
    let isDropped := state.eventLimit.any (event.index ≥ ·)
    set {
      state with
      events := if isDropped then state.events else state.events.push event
      droppedEvents := if isDropped then state.droppedEvents + 1 else state.droppedEvents
      stacks := state.stacks.insert event.threadId stack
      eventDepths :=
        if isDropped then state.eventDepths.erase event.index else state.eventDepths
    }

/-- Return completed events in reservation order rather than completion order. -/
public def capturedEvents : IO (Array Event) :=
  profilerState.atomically do
    let state ← get
    pure <| state.events.qsort (fun a b => a.index < b.index)

/--
Discard the current capture and begin another one.

The caller must keep recording disabled until the reset completes. This prevents a newly admitted
span from being erased by session setup.
-/
public def resetCapture (eventLimit : Option Nat) : IO Unit := do
  let start ← sampleProcess
  profilerState.atomically do
    set ({ eventLimit, processStart := some start } : ProfilerState)

/-- Read event-limit accounting and whole-process resource changes for the current capture. -/
public def captureStatus : IO CaptureStatus := do
  let finish ← sampleProcess
  profilerState.atomically do
    let state ← get
    pure {
      process := state.processStart.map (processDelta finish)
      eventLimit := state.eventLimit
      droppedEvents := state.droppedEvents
    }

/-- Claim the right to write the current report. Only one concurrent finisher succeeds. -/
public def claimReport : IO Bool :=
  profilerState.atomically do
    let state ← get
    if state.reportClaimed then
      pure false
    else
      set { state with reportClaimed := true }
      pure true

/-- Allow another report attempt after an export failure. -/
public def releaseReportClaim : IO Unit :=
  profilerState.atomically do
    modify fun state => { state with reportClaimed := false }

end Internal

/-- Operating-system process identifier used by exported Trace Event records. -/
public def currentProcessId : UInt32 :=
  Internal.processId

/--
Run an action under dynamically scoped event metadata and an optional logical parent.

An explicit field in `metadata` overrides the surrounding context. The previous context is restored
even when the action throws. `parentIndex` is useful when a task is spawned on another Lean thread;
cross-thread links are kept for correlation but are not subtracted from exclusive thread time.
-/
public def withContext {α : Type} (metadata : Metadata := {}) (parentIndex : Option Nat := none)
    (action : IO α) : IO α := do
  let threadId ← IO.getTID
  let previous ← Internal.profilerState.atomically do
    let state ← get
    let previous := state.contexts.getD threadId ({}, none)
    let combined := (metadata.withFallback previous.1, parentIndex <|> previous.2)
    set { state with contexts := state.contexts.insert threadId combined }
    pure previous
  try
    action
  finally
    Internal.profilerState.atomically do
      modify fun state =>
        { state with contexts := state.contexts.insert threadId previous }

/-- Attach a training or inference step number to nested spans. -/
public def withStep {α : Type} (step : Nat) (action : IO α) : IO α :=
  withContext (metadata := { stepIndex := some step }) (action := action)

/-- Attach a model or layer name to nested spans. -/
public def withModule {α : Type} (name : String) (action : IO α) : IO α :=
  withContext (metadata := { moduleName := some name }) (action := action)

/-- Attach a phase such as `forward`, `backward`, or `optimizer` to nested spans. -/
public def withPhase {α : Type} (phase : String) (action : IO α) : IO α :=
  withContext (metadata := { phase := some phase }) (action := action)

/-- Give spans in `action` a logical parent that may have been created on another thread. -/
public def withParentIndex {α : Type} (parentIndex : Nat) (action : IO α) : IO α :=
  withContext (parentIndex := some parentIndex) (action := action)

/-- Index of the innermost span currently active on this thread. -/
public def currentSpanIndex : IO (Option Nat) := do
  let threadId ← IO.getTID
  Internal.profilerState.atomically do
    let state ← get
    pure (state.stacks.getD threadId #[]).back?

end LeanProfiler
