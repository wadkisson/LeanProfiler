/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Session
public import Lean

/-!
# Instrumentation syntax

`span "name" action` times one expression. `profiled def` wraps a function, and a profiled
declaration named `main` also owns report setup and export.
-/

@[expose] public section

namespace LeanProfiler

open Lean

namespace Internal

/--
Run an instrumented action whose construction should happen inside the measured interval.

`profiled def` uses this thunked form so evaluating the declaration body happens after timing
starts.
-/
def spanThunk {α : Type} (name : String) (make : Unit → IO α)
    (metadata : Metadata := {}) (hooks : SpanHooks := SpanHooks.none) : IO α := do
  if ← profilingIsEnabled then
    recordSpanWithHooks name metadata hooks (make ())
  else
    make ()

end Internal

/--
Time an `IO` action.

Timing starts immediately before the action is executed. Metadata and hooks are optional named
arguments.
-/
def span {α : Type} (name : String) (action : IO α)
    (metadata : Metadata := {}) (hooks : SpanHooks := SpanHooks.none) : IO α :=
  Internal.spanThunk name (fun _ => action) metadata hooks

/--
Define an `IO` function with a span named after the declaration.

The generated definition must return `IO`; inferred and aliased `IO` result types work without
syntax inspection. Pure declarations are rejected. Use an ordinary `def` and place `span` around
the `IO` boundary that forces the pure computation.
-/
macro modifiers:declModifiers "profiled " "def " id:declId signature:optDeclSig
    " := " body:term : command => do
  let declarationName := id.raw[0].getId
  let spanName := Syntax.mkStrLit declarationName.toString
  if declarationName == `main then
    `($modifiers:declModifiers def $id:declId $signature:optDeclSig :=
        LeanProfiler.Internal.runSession LeanProfiler.startupConfig $spanName (fun _ => $body))
  else
    `($modifiers:declModifiers def $id:declId $signature:optDeclSig :=
        LeanProfiler.Internal.spanThunk $spanName (fun _ => $body))

end LeanProfiler
