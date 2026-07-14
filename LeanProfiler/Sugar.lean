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
