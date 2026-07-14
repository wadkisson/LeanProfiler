/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
-/

module

public import LeanProfiler.Runtime
public import Lean

/-!
# LeanProfiler Sugar

The minimal, near-zero-overhead ergonomic layer over `LeanProfiler.Runtime`. There are exactly
**two** names to learn:

* `profiled def f := ...` — profile a whole function.
  * On a normal function it times the body under a span named after the function.
  * On `main` it becomes the on-switch: `clear` on entry, `finish .all` on exit.
* `span "name" (expr)` — sub-profile a piece. `expr` is any normal expression, pure or `IO`, and is
  timed correctly either way (pure work is forced *inside* the span so the optimizer cannot float it
  out).

Everything is gated on the `LEAN_PROFILE` environment variable, read once at startup:

```text
LEAN_PROFILE=1 lake exe myapp   # records, writes summary + trace + HTML at exit
lake exe myapp                  # off: every instrumented call is a single boolean check
```

Need per-span metadata (phase/shapes/memory) or a fully manual API? Drop down to
`LeanProfiler.Runtime` (`recordSpanWith`, `withModule`, …) — see the README.
-/

@[expose] public section

namespace LeanProfiler

open Lean

/-- Whether profiling is active for this process. Read once from `LEAN_PROFILE` at startup:
unset, `""`, `"0"`, or `"false"` mean off; anything else means on. -/
initialize profilingEnabled : Bool ← do
  match ← IO.getEnv "LEAN_PROFILE" with
  | some v => pure (v != "" && v != "0" && v != "false")
  | none => pure false

/-- Trace output path, from `LEAN_PROFILE_OUT` (default `build/leanprofiler-trace.json`). The HTML
report is written to this path followed by `.html`. -/
initialize profileOutputPath : String ← do
  pure ((← IO.getEnv "LEAN_PROFILE_OUT").getD "build/leanprofiler-trace.json")

/-- Internal: how `span` runs an expression, pure or `IO`. You never write this instance yourself. -/
class Spannable (β : Type) (α : outParam Type) where
  toIO : β → IO α
  toSpanAction : β → IO α

/-- An `IO` action — run it inside the span. -/
instance (priority := 100) {α : Type} : Spannable (IO α) α where
  toIO := id
  toSpanAction := id

/-- A pure value — force its evaluation inside the span via `IO.lazyPure`. -/
instance (priority := 10000) {α : Type} : Spannable α α where
  toIO := pure
  toSpanAction := fun value => IO.lazyPure (fun _ => value)

/-- Backing definition for the `span` macro; prefer the macro. Records under `name` only when
profiling is enabled, otherwise just runs the code. It also takes optional `metadata`
(phase/shapes/memory): call it directly — `spanCore "name" expr meta` — when you need that. -/
@[inline] def spanCore {β : Type} {α : Type} [Spannable β α]
    (name : String) (body : β) (metadata : Metadata := {}) : IO α :=
  if profilingEnabled then
    recordSpanWith name metadata (Spannable.toSpanAction body)
  else
    Spannable.toIO body

/-- Run a pure `spanCore` from pure code when profiling is enabled. Unsafe: only used behind the
`profiled def` macro for non-`IO` return types. -/
unsafe def evalSpan {α : Type} [Inhabited α] (name : String) (body : α) : α :=
  match unsafeIO (spanCore name body) with
  | .ok a => a
  | .error e => panic e.toString

/-- Sub-profile a piece of code under `name`. Write **any** expression — pure or `IO`, no special
syntax — and it is timed correctly:

```lean
let y ← span "matmul" (matmul w x)     -- pure kernel, forced inside the span
let _ ← span "load" (loadBatch n)      -- IO action, run inside the span
```

Records only when profiling is enabled; otherwise it just runs your code. For per-span metadata,
call `spanCore` or `recordSpanWith` directly. -/
macro "span " name:term:max body:term:max : term =>
  `(LeanProfiler.spanCore $name $body)

/-- Wrap a program entry point: `clear` on entry and `finish .all` on exit (even if the body
throws), but only when profiling is enabled. When disabled this is just `action`. This is what
`profiled def main` expands into; you never need to call it directly. -/
def withProfiledMain {α : Type} (action : IO α) : IO α := do
  unless profilingEnabled do
    return ← action
  clear
  try
    action
  finally
    finish .all profileOutputPath

private meta partial def typeStxIsIO (stx : Syntax) : Bool :=
  match stx with
  | `(IO $_) => true
  | stx => stx.getArgs.any typeStxIsIO

private meta def optDeclSigReturnsIO? (sig : Syntax) : Bool :=
  match sig with
  | `(optDeclSig| $_binders* : $type) => typeStxIsIO type
  | `(optDeclSig| : $type) => typeStxIsIO type
  | _ => false

/-- `profiled def f args := body` profiles a whole function.

* On `main` it expands to `withProfiledMain body` — the on-switch that clears on entry and writes
  the report on exit.
* On any other function it times the whole body under a span named after the function. -/
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
