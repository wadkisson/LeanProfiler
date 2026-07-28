/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

import VersoManual
import LeanProfilerGuide.GettingStarted
import LeanProfilerGuide.Capture
import LeanProfilerGuide.Results
import LeanProfilerGuide.Regressions
import LeanProfilerGuide.ProfilerComparison
import LeanProfilerGuide.TorchLean

open Verso.Genre Manual

#doc (Manual) "LeanProfiler" =>
%%%
shortTitle := "LeanProfiler"
tag := "leanprofiler"
%%%

A command that finished quickly last week now takes twice as long. Timing `main` confirms the
regression, but it says nothing about where the extra time went. The delay may be in data
preparation, Lean code, a foreign runtime, device queueing, or the synchronization that joins those
pieces.

LeanProfiler records boundaries named by the running Lean program. A training command can separate
`batch.load` from `model.forward`, keep their nesting and metadata, and measure elapsed time
alongside Lean heartbeats. Each capture produces a timeline that opens in Perfetto and a strict
summary that can be compared in a script or CI job.

![A profiling investigation that begins with a slowdown question and ends with a diagnosis or regression gate](Assets/profiling-workflow.svg)

The running example begins with three loads and three forward calls. We turn that small capture into
a nested trace, read its self and total time, change only the forward delay, and place a regression
gate on the resulting summary. The checked-in artifacts come from real executions. Their structure
is reproducible; their exact durations belong to the machine and run that produced them.

This is a runtime profiler. If a theorem is slow to elaborate, use Lean's compiler and elaborator
profilers. If a PyTorch call is slow inside a foreign boundary, use PyTorch Profiler or a native
device profiler for operator and kernel detail. LeanProfiler supplies the application-level view
that connects those narrower measurements.

{include 1 LeanProfilerGuide.GettingStarted}

{include 1 LeanProfilerGuide.Capture}

{include 1 LeanProfilerGuide.Results}

{include 1 LeanProfilerGuide.Regressions}

{include 1 LeanProfilerGuide.ProfilerComparison}

{include 1 LeanProfilerGuide.TorchLean}
