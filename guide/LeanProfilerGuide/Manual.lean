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

Lean's compiler profilers explain time spent elaborating and type-checking a source file. Once that
work is finished, a compiled Lean program may read data, search a state space, serve requests, run a
simulation, wait for worker tasks, or cross into a foreign runtime. When the whole command becomes
slower, its total duration says little about which of those phases changed.

LeanProfiler lets the running program name those phases. A file indexer might record
`source.discover`, `source.parse`, and `index.write`; a server might record request parsing, lookup,
and serialization. The resulting trace keeps nesting, threads, metadata, elapsed time, and Lean
heartbeats. A separate summary groups repeated work so two runs can be compared without parsing a
timeline by hand.

![A profiling investigation that begins with a slowdown question and ends with a diagnosis or regression gate](Assets/profiling-workflow.svg)

Consider a small source indexer that reads and analyzes three files. Its repeated phases make the
timing rules easy to see. We will capture the run, distinguish self time from total time, slow down
one phase, and compare the two summaries. The checked-in artifacts come from real executions; their
exact durations belong to the machine and run that produced them.

This is a runtime profiler. If a theorem is slow to elaborate, use Lean's compiler and elaborator
profilers. If code inside a foreign boundary is slow, use that runtime's profiler for lower-level
detail. The outer LeanProfiler span still shows how long the Lean caller waited and where that call
belongs in the rest of the run.

{include 1 LeanProfilerGuide.GettingStarted}

{include 1 LeanProfilerGuide.Capture}

{include 1 LeanProfilerGuide.Results}

{include 1 LeanProfilerGuide.Regressions}

{include 1 LeanProfilerGuide.ProfilerComparison}

{include 1 LeanProfilerGuide.TorchLean}
