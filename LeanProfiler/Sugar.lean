/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
-/

module

public import LeanProfiler.Runtime
public import Lean

/-!
# LeanProfiler Sugar

Two names:

* `profiled def f := ...` — profile a whole function (on `main`: clear + finish).
* `span "name" (expr)` — time any expression, pure or `IO`.

Gated by `LEAN_PROFILE` (`unset`/`""`/`"0"`/`"false"` = off).
-/

@[expose] public section

namespace LeanProfiler

open Lean

/-- Whether profiling is active. Read once from `LEAN_PROFILE` at startup. -/
initialize profilingEnabled : Bool ← do
  match ← IO.getEnv "LEAN_PROFILE" with
  | some v => pure (v != "" && v != "0" && v != "false")
  | none => pure false

/-- Trace path from `LEAN_PROFILE_OUT` (default `build/leanprofiler-trace.json`). -/
initialize profileOutputPath : String ← do
  pure ((← IO.getEnv "LEAN_PROFILE_OUT").getD "build/leanprofiler-trace.json")

/-- How `span` runs an expression, pure or `IO`. -/
class Spannable (β : Type) (α : outParam Type) where
  toIO : β → IO α
  toSpanAction : β → IO α

/-- Pure value — force evaluation inside the span via `IO.lazyPure`.

Lower priority than the `IO` instance so `IO α` is not treated as a pure value. -/
instance (priority := 100) {α : Type} : Spannable α α where
  toIO := pure
  toSpanAction := fun value => IO.lazyPure (fun _ => value)

/-- `IO` action — run it inside the span. -/
instance (priority := 1000) {α : Type} : Spannable (IO α) α where
  toIO := id
  toSpanAction := id

/-- Record under `name` when profiling is enabled; otherwise just run the code. -/
@[inline] def spanCore {β : Type} {α : Type} [Spannable β α]
    (name : String) (body : β) : IO α :=
  if profilingEnabled then
    recordSpan name (Spannable.toSpanAction body)
  else
    Spannable.toIO body

/-- Unsafe pure entry for `profiled def` on non-`IO` return types. -/
unsafe def evalSpan {α : Type} [Inhabited α] (name : String) (body : α) : α :=
  match unsafeIO (spanCore name body) with
  | .ok a => a
  | .error e => panic e.toString

/-- Time any expression under `name`. -/
macro "span " name:term:max body:term:max : term =>
  `(LeanProfiler.spanCore $name $body)

/-- Clear on entry and `finish` on exit when profiling is enabled. -/
def withProfiledMain {α : Type} (action : IO α) : IO α := do
  unless profilingEnabled do
    return ← action
  clear
  try
    action
  finally
    finish profileOutputPath

private meta partial def typeStxIsIO (stx : Syntax) : Bool :=
  match stx with
  | `(IO $_) => true
  | stx => stx.getArgs.any typeStxIsIO

private meta def optDeclSigReturnsIO? (sig : Syntax) : Bool :=
  match sig with
  | `(optDeclSig| $_binders* : $type) => typeStxIsIO type
  | `(optDeclSig| : $type) => typeStxIsIO type
  | _ => false

/-- `profiled def f := body` — whole-function span; on `main`, also clear/finish. -/
macro mods:declModifiers "profiled " "def " id:declId sig:optDeclSig " := " body:term : command => do
  let name := id.raw[0].getId
  if name == `main then
    `($mods:declModifiers def $id:declId $sig:optDeclSig := LeanProfiler.withProfiledMain $body)
  else
    let spanName := Syntax.mkStrLit name.toString
    if optDeclSigReturnsIO? sig then
      `($mods:declModifiers def $id:declId $sig:optDeclSig :=
          LeanProfiler.spanCore $spanName $body)
    else
      `($mods:declModifiers def $id:declId $sig:optDeclSig :=
          if LeanProfiler.profilingEnabled then
            unsafe (LeanProfiler.evalSpan $spanName $body)
          else
            $body)

end LeanProfiler
