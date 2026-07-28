/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfiler.Output
import LeanProfiler.Tests.Support

/-!
# Trace Event export tests

Checks timestamp precision, escaping, metadata events, and process identifiers.
-/

namespace LeanProfiler.Tests.TraceEvent

open LeanProfiler
open Lean

abbrev expect := LeanProfiler.Tests.expect "trace"

/-- Run Trace Event precision, escaping, and metadata checks. -/
public def run : IO Unit := do
  let report := analyze #[
    {
      name := "origin"
      startNs := 100000
      endNs := 100500
      depth := 0
      index := 0
      threadId := 3
    },
    {
      name := "quote \" newline\n"
      startNs := 101234
      endNs := 105801
      depth := 0
      index := 1
      threadId := 3
    }
  ]
  let encoded := Json.compress (traceJson report)
  expect "trace parses as JSON" (Json.parse encoded).isOk
  expect "timestamp uses fractional microseconds" (encoded.contains "\"ts\":1.234")
  expect "duration uses fractional microseconds" (encoded.contains "\"dur\":4.567")
  expect "event name is escaped" (encoded.contains "quote \\\" newline\\n")
  expect "process metadata emitted" (encoded.contains "\"name\":\"process_name\"")
  expect "thread metadata emitted" (encoded.contains "\"name\":\"thread_name\"")
  expect "operating-system process id emitted"
    (encoded.contains s!"\"pid\":{currentProcessId}")
  let namedTrace := Json.compress (traceJson report "training worker")
  expect "configured process name emitted"
    (namedTrace.contains "\"name\":\"training worker\"")
  let summary := Json.compress (summaryJson report)
  expect "summary preserves integer nanoseconds"
    (summary.contains "\"trace_window_ns\":5801")

end LeanProfiler.Tests.TraceEvent
