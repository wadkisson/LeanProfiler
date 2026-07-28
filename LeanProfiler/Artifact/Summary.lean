/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Analysis.Report

/-!
# Decoded summary model

Summary files retain grouped rows and capture context. Full event records remain in the trace.
-/

namespace LeanProfiler

/-- Per-event values retained by a summary file. The event itself remains in the trace artifact. -/
public structure ArtifactEventTiming where
  eventIndex : Nat
  inclusiveNs : Nat
  selfNs : Nat
  inclusiveHeartbeats : Nat
  selfHeartbeats : Nat
  deriving Repr, Inhabited, DecidableEq

/--
Decoded version-1 summary.

The grouped `rows` support comparisons. The remaining fields keep enough capture context to check
an artifact before accepting it as a baseline.
-/
public structure SummaryArtifact where
  eventCount : Nat
  threadCount : Nat
  maxDepth : Nat
  traceOriginNs : Nat
  traceWindowNs : Nat
  recordedThreadNs : Nat
  recordedHeartbeats : Nat
  eventLimit : Option Nat
  droppedEvents : Nat
  process : Option ProcessMetrics
  issues : Array ValidationIssue
  eventTimings : Array ArtifactEventTiming
  rows : Array SummaryRow
  deriving Repr, Inhabited

end LeanProfiler
