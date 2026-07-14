/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
-/

module

public import LeanProfiler.Runtime
public import Lean

/-!
# LeanProfiler Sugar

The minimal, near-zero-overhead ergonomic layer over `LeanProfiler.Runtime`. Two profiling modes
plus one on-switch:

* `profiled def f := ...`  — automatic: profile a whole function (span named after it).
* `span "name" do ...`     — manual: profile a block (dynamic name; optional metadata).
* `profiled_main def main := ...` — the on-switch: `clear` on entry, `finish .all` on exit.

For **pure** computations (numeric kernels, tensor ops), whose evaluation the optimizer would
otherwise float out of a span, use `spanPure` (in an `IO` block) or `timePure` (from pure code).

Everything is gated on the `LEAN_PROFILE` environment variable, read once at startup:

```text
LEAN_PROFILE=1 lake exe myapp   # records, writes summary + trace + HTML at exit
lake exe myapp                  # off: every instrumented call is a single boolean check
```
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

/-- Record a span for `action` under a runtime-chosen `name`, only when profiling is enabled;
otherwise run `action` directly with no overhead. This is the one manual combinator: use it for a
per-iteration/per-layer breakdown (`span layer.name do ...` in a loop) or around any block. Pass
optional `metadata` for shapes/phase/memory that enrich the report. It is also what `profiled`
expands into.

```lean
span "matmul" do runMatmul
span "matmul" (metadata := { phase := some "forward" }) do runMatmul
```
-/
@[inline] def span {α : Type} (name : String) (action : IO α) (metadata : Metadata := {}) : IO α :=
  if profilingEnabled then recordSpanWith name metadata action else action

/-- Profile a **pure** computation, attributing its evaluation time to a span.

Pure work is the trap in a strict-but-optimizing language: writing `span "k" (pure (kernel x))`
lets the compiler *float* `kernel x` out of the timed region, so the span reads ~0 and the cost
lands on whatever forces the value later. `spanPure` avoids this by taking a thunk and forcing it
*inside* the span via `IO.lazyPure` (an application the optimizer cannot hoist):

```lean
let y ← spanPure "matmul" (fun _ => matmul w x)
let y ← spanPure "matmul" (metadata := { shape := some "[512,512]" }) (fun _ => matmul w x)
```

Forcing is to **WHNF**. That fully evaluates strictly-built data (any `Array`/`FloatArray`/`Nat`/
strict structure a numeric kernel returns). Values with lazy sub-structure (a lazy `List` spine,
an unforced `Thunk`) are only forced at the top; force those yourself inside the thunk if needed.
Note also that a *closed constant* expression (no runtime inputs) is floated to a top-level thunk
and memoized, so it is timed only on first evaluation — real kernels close over their inputs and
are unaffected. When profiling is off this is exactly `IO.lazyPure thunk` (no overhead). -/
@[inline] def spanPure {α : Type} (name : String) (thunk : Unit → α)
    (metadata : Metadata := {}) : IO α :=
  span name (IO.lazyPure thunk) metadata

private unsafe def timePureImpl {α : Type} (name : String) (thunk : Unit → α)
    (metadata : Metadata := {}) : α :=
  if profilingEnabled then
    match unsafeIO (recordSpanWith name metadata (IO.lazyPure thunk)) with
    | .ok a => a
    | .error _ => thunk ()
  else
    thunk ()

/-- Profile a pure computation **from a pure call site** — no `IO` in the signature.

This is `spanPure` for code that isn't in `IO`: it returns `α`, so you can drop it into an ordinary
pure kernel and still get its time in the report. It works by recording via unsafe IO under the
hood (`@[implemented_by]`), so it carries the usual `unsafeIO` caveats: the compiler is free to
reorder, duplicate, or drop the timing side effect, and closed-constant expressions may be timed
once and memoized. Prefer `spanPure` whenever you already have an `IO` context; reach for `timePure`
only to instrument pure code you don't want to thread `IO` through. When profiling is off it is
exactly `thunk ()`.

```lean
def forward (x : Tensor) : Tensor :=
  let h := timePure "attn" (fun _ => attention x)
  timePure "mlp" (fun _ => mlp h)
```
-/
@[implemented_by timePureImpl]
def timePure {α : Type} (name : String) (thunk : Unit → α)
    (metadata : Metadata := {}) : α := thunk ()

/-- Wrap a program entry point: `clear` on entry and `finish .all` on exit (even if the body
throws), but only when profiling is enabled. When disabled this is just `action`. -/
def withProfiledMain {α : Type} (action : IO α) : IO α := do
  unless profilingEnabled do
    return ← action
  clear
  try
    action
  finally
    finish .all profileOutputPath

/-- `profiled def f args : IO α := body` ⟶ `def f args : IO α := span "f" body`. -/
macro mods:declModifiers "profiled " "def " id:declId sig:optDeclSig " := " body:term : command => do
  let spanName := Syntax.mkStrLit (id.raw[0].getId).toString
  `($mods:declModifiers def $id:declId $sig:optDeclSig := LeanProfiler.span $spanName (action := $body))

/-- `profiled_main def main args := body` ⟶ `def main args := withProfiledMain body`. -/
macro mods:declModifiers "profiled_main " "def " id:declId sig:optDeclSig " := " body:term : command => do
  `($mods:declModifiers def $id:declId $sig:optDeclSig := LeanProfiler.withProfiledMain $body)

end LeanProfiler
