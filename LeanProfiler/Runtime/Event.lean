/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

/-!
# Recorded events

The event model is independent of report analysis and file formats. It can be used by custom
instrumentation without pulling in either exporter.
-/

namespace LeanProfiler

/--
Structured labels and optional runtime counters attached to an event.

The profiler does not interpret device memory fields. Device-specific code can populate them
through hooks without adding a device-runtime dependency to the capture layer.
-/
public structure Metadata where
  phase : Option String := none
  activity : Option String := none
  backend : Option String := none
  dtype : Option String := none
  device : Option String := none
  timing : Option String := none
  moduleName : Option String := none
  graphNode : Option String := none
  stepIndex : Option Nat := none
  inputShapes : Array String := #[]
  outputShapes : Array String := #[]
  allocBytes : Option Nat := none
  allocLiveBytes : Option Nat := none
  allocPeakBytes : Option Nat := none
  allocDeltaBytes : Option Int := none
  hookError : Option String := none
  deriving Repr, Inhabited, DecidableEq

/-- Fill absent fields in `explicit` from dynamically scoped metadata. -/
public def Metadata.withFallback (explicit inherited : Metadata) : Metadata :=
  {
    phase := explicit.phase <|> inherited.phase
    activity := explicit.activity <|> inherited.activity
    backend := explicit.backend <|> inherited.backend
    dtype := explicit.dtype <|> inherited.dtype
    device := explicit.device <|> inherited.device
    timing := explicit.timing <|> inherited.timing
    moduleName := explicit.moduleName <|> inherited.moduleName
    graphNode := explicit.graphNode <|> inherited.graphNode
    stepIndex := explicit.stepIndex <|> inherited.stepIndex
    inputShapes :=
      if explicit.inputShapes.isEmpty then inherited.inputShapes else explicit.inputShapes
    outputShapes :=
      if explicit.outputShapes.isEmpty then inherited.outputShapes else explicit.outputShapes
    allocBytes := explicit.allocBytes <|> inherited.allocBytes
    allocLiveBytes := explicit.allocLiveBytes <|> inherited.allocLiveBytes
    allocPeakBytes := explicit.allocPeakBytes <|> inherited.allocPeakBytes
    allocDeltaBytes := explicit.allocDeltaBytes <|> inherited.allocDeltaBytes
    hookError := explicit.hookError <|> inherited.hookError
  }

/--
A completed timed region.

`startNs` and `endNs` use the process monotonic clock. `index` is assigned when the span starts,
which keeps parent links stable even though events are stored in completion order.
-/
public structure Event where
  name : String
  startNs : Nat
  endNs : Nat
  depth : Nat
  index : Nat
  parentIndex : Option Nat := none
  threadId : UInt64 := 0
  heartbeats : Nat := 0
  metadata : Metadata := {}
  deriving Repr, Inhabited, DecidableEq

/-- Inclusive span duration in nanoseconds. Malformed reversed intervals have duration zero. -/
public def Event.durationNs (event : Event) : Nat :=
  event.endNs - event.startNs

end LeanProfiler
