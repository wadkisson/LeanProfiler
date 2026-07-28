/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

import LeanProfiler.Tests.Analysis
import LeanProfiler.Tests.Artifact
import LeanProfiler.Tests.CLI
import LeanProfiler.Tests.Comparison
import LeanProfiler.Tests.Instrumentation
import LeanProfiler.Tests.Proofs
import LeanProfiler.Tests.Runtime
import LeanProfiler.Tests.Schedule
import LeanProfiler.Tests.ScheduledSession
import LeanProfiler.Tests.Session
import LeanProfiler.Tests.TraceEvent

/-!
# LeanProfiler test driver

Runs every core test module in a fixed order.
-/

/-- Run the LeanProfiler test suites. -/
unsafe def main : IO Unit := do
  LeanProfiler.Tests.Analysis.run
  LeanProfiler.Tests.Artifact.run
  LeanProfiler.Tests.CLI.run
  LeanProfiler.Tests.Comparison.run
  LeanProfiler.Tests.Instrumentation.run
  LeanProfiler.Tests.Runtime.run
  LeanProfiler.Tests.Schedule.run
  LeanProfiler.Tests.ScheduledSession.run
  LeanProfiler.Tests.Session.run
  LeanProfiler.Tests.TraceEvent.run
  IO.println "LeanProfiler tests passed"
