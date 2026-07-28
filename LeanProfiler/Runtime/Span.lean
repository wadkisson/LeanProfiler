/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Runtime.Capture

/-!
# Span timing

A span measures monotonic host time and Lean heartbeats. Hooks can synchronize an asynchronous
device or attach allocator counters while keeping those policies outside the capture engine.
-/

namespace LeanProfiler

/--
Extension points around one timed action.

`prepare` runs before timing starts. `completeTiming` runs before the stop timestamp and can
synchronize an asynchronous device. `enrich` runs after the stop timestamp and can attach allocator
snapshots without charging their collection time to the span.
-/
public structure SpanHooks where
  State : Type
  prepare : IO State
  completeTiming : State → IO Unit := fun _ => pure ()
  enrich : State → Metadata → IO Metadata := fun _ metadata => pure metadata

/-- Hooks that do no extra work. -/
public def SpanHooks.none : SpanHooks where
  State := Unit
  prepare := pure ()

namespace Internal

/-- Preserve every hook diagnostic when more than one hook phase fails. -/
def combineHookErrors (first second : Option String) : Option String :=
  match first, second with
  | none, error | error, none => error
  | some first, some second => some s!"{first}; {second}"

/--
Run `action` and record time, Lean heartbeats, metadata, and nesting.

Lean heartbeats count small allocations on the current execution thread, with extra weight for some
allocation-avoiding work. They are useful as a stable work counter, but they are not bytes or CPU
cycles. Hook failures are recorded in metadata and do not replace an exception from `action`.
-/
public def recordSpanWithHooks {α : Type} (name : String) (metadata : Metadata)
    (hooks : SpanHooks) (action : IO α) : IO α := do
  let hookState ← hooks.prepare
  let reservation ← reserveSpan
  let startHeartbeats ← IO.getNumHeartbeats
  let startNs ← IO.monoNanosNow
  try
    action
  finally
    let hookError ←
      try
        hooks.completeTiming hookState
        pure none
      catch error =>
        pure (some s!"completeTiming: {error}")
    let endNs ← IO.monoNanosNow
    let endHeartbeats ← IO.getNumHeartbeats
    let enriched ←
      try
        hooks.enrich hookState metadata
      catch error =>
        pure {
          metadata with
          hookError := combineHookErrors metadata.hookError (some s!"enrich: {error}")
        }
    let enriched := {
      enriched with
      hookError := combineHookErrors hookError enriched.hookError
    }
    completeSpan {
      name
      startNs
      endNs
      depth := reservation.depth
      index := reservation.index
      parentIndex := reservation.parentIndex
      threadId := reservation.threadId
      heartbeats := endHeartbeats - startHeartbeats
      metadata := enriched.withFallback reservation.metadata
    }

/-- Record a span with structured metadata and no extension hooks. -/
public def recordSpanWith {α : Type} (name : String) (metadata : Metadata := {})
    (action : IO α) : IO α :=
  recordSpanWithHooks name metadata SpanHooks.none action

/-- Record a host span with no metadata. -/
public def recordSpan {α : Type} (name : String) (action : IO α) : IO α :=
  recordSpanWith name {} action

end Internal
end LeanProfiler
