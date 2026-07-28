/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Analysis
public import LeanProfiler.Config
public import Lean.Data.Json
public import LeanProfiler.Output.Terminal
public import LeanProfiler.Output.TraceEvent
public import LeanProfiler.Output.SummaryJson
public import LeanProfiler.Output.Export

/-!
# Reports and artifacts

Terminal summaries, Trace Event output, versioned summary JSON, and file export. Durations remain
integer nanoseconds except where Trace Event requires microseconds.
-/
