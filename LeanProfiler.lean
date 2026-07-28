/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Config
public import LeanProfiler.Runtime
public import LeanProfiler.Analysis
public import LeanProfiler.Output
public import LeanProfiler.Session
public import LeanProfiler.Instrumentation
public import LeanProfiler.Schedule
public import LeanProfiler.ScheduledSession
public import LeanProfiler.Comparison
public import LeanProfiler.Artifact

/-!
# LeanProfiler

Span capture, report analysis and export, scheduled sessions, and artifact comparison.

The umbrella import contains the runtime API used by applications. Command elaboration, the
standalone command router, and theorem collections are separate imports:

- `LeanProfiler.Syntax` provides `profiled def`;
- `LeanProfiler.CLI` provides the embeddable command router;
- `LeanProfiler.Proofs` provides laws about schedules, comparisons, and timing analysis.
-/
