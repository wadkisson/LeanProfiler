/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfiler.Output
import LeanProfiler.Tests.Support

/-!
# Timing analysis tests

Checks nested timing, grouping, percentiles, and malformed event diagnostics.
-/

namespace LeanProfiler.Tests.Analysis

open LeanProfiler

abbrev expect := LeanProfiler.Tests.expect "analysis"

def event (name : String) (startNs endNs depth index : Nat)
    (parent : Option Nat := none) (threadId : UInt64 := 7) : Event :=
  { name, startNs, endNs, depth, index, parentIndex := parent, threadId }

/-- Run timing analysis and malformed-event checks. -/
public def run : IO Unit := do
  let report := analyze #[
    event "outer" 1000 11000 0 0,
    event "work" 2000 5000 1 1 (some 0),
    event "work" 6000 8000 1 2 (some 0)
  ]
  expect "valid event forest" report.issues.isEmpty
  expect "trace window" (report.traceWindowNs == 10000)
  expect "recorded thread time" (report.recordedThreadNs == 10000)
  expect "outer exclusive time" (report.timings[0]!.selfNs == 5000)
  expect "grouped call count"
    (report.rows.any fun row => row.key.name == "work" && row.calls == 2)
  expect "nearest-rank p95"
    (report.rows.any fun row => row.key.name == "work" && row.p95Ns == 3000)

  let malformed := analyze #[
    event "parent" 0 10 0 0,
    event "left" 1 8 1 1 (some 0),
    event "right" 5 9 1 2 (some 0)
  ]
  expect "overlapping children use interval union"
    (malformed.timings[0]!.selfNs == 2)
  expect "overlapping siblings are reported"
    (malformed.issues.any fun problem => problem.message.contains "overlap")

  let overlappingRoots := analyze #[
    event "first-root" 0 10 0 0,
    event "second-root" 5 15 0 1
  ]
  expect "overlapping roots on one thread are reported"
    (overlappingRoots.issues.any fun problem => problem.message.contains "overlap")

  let outsideParent := analyze #[
    event "parent" 100 200 0 0,
    event "outside" 10 50 1 1 (some 0)
  ]
  expect "time outside a malformed parent is not subtracted"
    (outsideParent.timings[0]!.selfNs == 100)
  expect "outside child is reported"
    (outsideParent.issues.any fun problem => problem.message.contains "outside parent")

  let missingParent := analyze #[event "orphan" 2 3 1 4 (some 9)]
  expect "missing parent is reported"
    (missingParent.issues.any fun problem => problem.message.contains "missing")

  let crossThread := analyze #[
    event "dispatch" 0 10 0 0 (threadId := 1),
    event "worker" 5 20 1 1 (some 0) (threadId := 2),
    event "worker.inner" 6 7 2 2 (some 1) (threadId := 2)
  ]
  expect "cross-thread child may outlive logical parent" crossThread.issues.isEmpty
  expect "cross-thread work is not subtracted from parent"
    (crossThread.timings[0]!.selfNs == 10)

end LeanProfiler.Tests.Analysis
