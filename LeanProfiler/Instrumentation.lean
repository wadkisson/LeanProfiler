/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Session

/-!
# Runtime instrumentation

`span "name" action` records one `IO` action when its surrounding session is enabled. This module
contains no command elaborators, so applications that use the function API do not load Lean's
compiler front end.
-/

namespace LeanProfiler

namespace Internal

/--
Run an instrumented action whose construction should happen inside the measured interval.

The `profiled def` command uses this thunked form so evaluating the declaration body happens after
timing starts.
-/
public def spanThunk {α : Type} (name : String) (make : Unit → IO α)
    (metadata : Metadata := {}) (hooks : SpanHooks := SpanHooks.none) : IO α := do
  if ← profilingIsEnabled then
    recordSpanWithHooks name metadata hooks (make ())
  else
    make ()

end Internal

/--
Time an `IO` action.

Timing starts immediately before the action is executed. Metadata and hooks are optional named
arguments. A span outside an enabled profiling session runs its action without retaining an event.
-/
public def span {α : Type} (name : String) (action : IO α)
    (metadata : Metadata := {}) (hooks : SpanHooks := SpanHooks.none) : IO α :=
  Internal.spanThunk name (fun _ => action) metadata hooks

end LeanProfiler
