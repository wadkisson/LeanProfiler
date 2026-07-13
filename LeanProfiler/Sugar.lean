/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
-/

module

public import LeanProfiler.Runtime
public import Lean

/-!
# LeanProfiler Sugar

An opt-in, near-zero-overhead ergonomic layer over `LeanProfiler.Runtime`.

The goal is the smallest possible user-facing surface:

```lean
import LeanProfiler
open LeanProfiler

profiled_main def main : IO Unit := do
  ...

profiled def slowStep (x : Thing) : IO Result := do
  ...
```

Then activate at runtime with an environment variable — no code changes to
toggle:

```text
LEAN_PROFILE=1 lake exe myapp          # records + writes trace/summary/HTML at exit
lake exe myapp                         # profiling off: macros are ~no-ops
```

This module adds **no** new recording, analysis, JSON, or HTML logic: it only
wraps the existing `recordSpanWith`, `clear`, and `finish` from
`LeanProfiler.Runtime`. When profiling is disabled every instrumented call
degrades to a single boolean check plus the original action.
-/

@[expose] public section

namespace LeanProfiler

open Lean

/-! ## Runtime gate

The gate is read exactly once at program startup so instrumented call sites pay
only a boolean load, not an environment lookup, per invocation. -/

/-- Whether profiling is active for this process. Read once from `LEAN_PROFILE`
at startup: unset, `""`, `"0"`, or `"false"` mean off; anything else means on. -/
initialize profilingEnabled : Bool ← do
  match ← IO.getEnv "LEAN_PROFILE" with
  | some v => pure (v != "" && v != "0" && v != "false")
  | none => pure false

/-- Trace output path, from `LEAN_PROFILE_OUT` (default
`build/leanprofiler-trace.json`). The HTML report is written to this path
followed by `.html`, exactly as `finish` already does. -/
initialize profileOutputPath : String ← do
  pure ((← IO.getEnv "LEAN_PROFILE_OUT").getD "build/leanprofiler-trace.json")

/-! ## Gated recording combinators -/

/-- Record a span only when profiling is enabled; otherwise run `action`
directly. This is the runtime primitive the `profiled` macro expands into, but
it is also usable by hand. -/
@[inline] def recordSpanGated {α : Type} (name : String) (metadata : Metadata := {})
    (action : IO α) : IO α :=
  if profilingEnabled then recordSpanWith name metadata action else action

/-- Wrap a program entry point: `clear` on entry and emit all artifacts with
`finish .all` on exit (even if the body throws), but only when profiling is
enabled. When disabled this is just `action`. -/
def withProfiledMain {α : Type} (action : IO α) : IO α := do
  unless profilingEnabled do
    return ← action
  clear
  try
    action
  finally
    finish .all profileOutputPath

/-! ## Surface macros

Lean does not cleanly support an attribute that rewrites a definition's body, so
the idiomatic realization of "mark this function for profiling" is a declaration
macro (in the same family as `partial def` / `noncomputable def`). `profiled def`
and `profiled_main def` desugar to a plain `def` with the body wrapped; the span
name is taken automatically from the declaration name. -/

/-- `profiled def f args : IO α := body` ⟶ `def f args : IO α := recordSpanGated "f" body`. -/
macro mods:declModifiers "profiled " "def " id:declId sig:optDeclSig " := " body:term : command => do
  let spanName := Syntax.mkStrLit (id.raw[0].getId).toString
  `($mods:declModifiers def $id:declId $sig:optDeclSig := LeanProfiler.recordSpanGated $spanName (action := $body))

/-- `profiled_main def main args := body` ⟶ `def main args := withProfiledMain body`. -/
macro mods:declModifiers "profiled_main " "def " id:declId sig:optDeclSig " := " body:term : command => do
  `($mods:declModifiers def $id:declId $sig:optDeclSig := LeanProfiler.withProfiledMain $body)

end LeanProfiler
