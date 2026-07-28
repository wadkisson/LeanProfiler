/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfiler
import LeanProfiler.Tests.Support

/-!
# Capture runtime tests

Checks nesting, metadata context, hooks, event limits, and cross-thread parents.
-/

namespace LeanProfiler.Tests.Runtime

open LeanProfiler
open LeanProfiler.Internal

abbrev expect := LeanProfiler.Tests.expect "runtime"

/-- Run capture-state, process-counter, metadata, hook, and nesting checks. -/
public def run : IO Unit := do
  let processStart : ProcessSnapshot := {
    userCpuMs := 20
    systemCpuMs := 10
    peakResidentSetSizeKb := 2048
    minorPageFaults := 40
    majorPageFaults := 3
    blockInputOps := 8
    blockOutputOps := 4
    voluntaryContextSwitches := 100
    involuntaryContextSwitches := 12
  }
  let processFinish : ProcessSnapshot := {
    userCpuMs := 27
    systemCpuMs := 8
    peakResidentSetSizeKb := 2560
    minorPageFaults := 35
    majorPageFaults := 5
    blockInputOps := 11
    blockOutputOps := 4
    voluntaryContextSwitches := 112
    involuntaryContextSwitches := 10
  }
  let processMetrics := processDelta processFinish processStart
  expect "process counters use saturating subtraction"
    (processMetrics.userCpuMs == 7 &&
      processMetrics.systemCpuMs == 0 &&
      processMetrics.minorPageFaults == 0 &&
      processMetrics.majorPageFaults == 2 &&
      processMetrics.blockInputOps == 3 &&
      processMetrics.blockOutputOps == 0 &&
      processMetrics.voluntaryContextSwitches == 12 &&
      processMetrics.involuntaryContextSwitches == 0)
  expect "process RSS reports the ending high-water mark and interval increase"
    (processMetrics.peakResidentSetSizeKb == 2560 &&
      processMetrics.peakResidentSetIncreaseKb == 512)
  let resetMetrics :=
    processDelta { processFinish with peakResidentSetSizeKb := 1024 } processStart
  expect "process RSS increase saturates if the operating system resets its counters"
    (resetMetrics.peakResidentSetSizeKb == 1024 &&
      resetMetrics.peakResidentSetIncreaseKb == 0)

  resetCapture none
  withStep 4 do
    recordSpanWith "outer" { phase := some "forward" } do
      withModule "linear.0" do
        recordSpan "inner" do
          pure ()
  let events ← capturedEvents
  expect "two events captured" (events.size == 2)
  expect "reservation order retained" (events[0]!.name == "outer" && events[1]!.name == "inner")
  expect "child parent index" (events[1]!.parentIndex == some events[0]!.index)
  expect "child depth" (events[1]!.depth == events[0]!.depth + 1)
  expect "same thread" (events[1]!.threadId == events[0]!.threadId)
  expect "explicit metadata retained" (events[0]!.metadata.phase == some "forward")
  expect "step context inherited" (events[1]!.metadata.stepIndex == some 4)
  expect "module context inherited" (events[1]!.metadata.moduleName == some "linear.0")

  resetCapture none
  let hooks : SpanHooks := {
    State := Nat
    prepare := pure 12
    enrich := fun before metadata =>
      pure { metadata with allocBytes := some (before + 30) }
  }
  recordSpanWithHooks "hooked" {} hooks (pure ())
  let hooked ← capturedEvents
  expect "hook metadata attached" (hooked[0]!.metadata.allocBytes == some 42)

  resetCapture none
  let failingHooks : SpanHooks := {
    State := Unit
    prepare := pure ()
    completeTiming := fun _ => throw <| IO.userError "completion failed"
    enrich := fun _ _ => throw <| IO.userError "enrichment failed"
  }
  recordSpanWithHooks "hook-errors" {} failingHooks (pure ())
  let hookErrors ← capturedEvents
  let messages := hookErrors[0]!.metadata.hookError.getD ""
  expect "all hook-phase errors are retained"
    (messages.contains "completeTiming: completion failed" &&
      messages.contains "enrich: enrichment failed")

  resetCapture (some 1)
  recordSpan "retained" (pure ())
  recordSpan "dropped" (pure ())
  let limited ← capturedEvents
  let status ← captureStatus
  expect "event limit retains prefix" (limited.size == 1 && limited[0]!.name == "retained")
  expect "event limit reports dropped spans" (status.droppedEvents == 1)
  expect "process resources sampled" status.process.isSome

  resetCapture none
  recordSpan "dispatch" do
    let some parent ← currentSpanIndex
      | throw <| IO.userError "active dispatch span has no index"
    let worker ← IO.asTask do
      withParentIndex parent do
        recordSpan "worker" do
          recordSpan "worker.inner" (pure ())
    match ← IO.wait worker with
    | .ok _ => pure ()
    | .error error => throw error
  let threaded ← capturedEvents
  let dispatch := threaded[0]!
  let worker := threaded[1]!
  let inner := threaded[2]!
  expect "worker links to dispatch" (worker.parentIndex == some dispatch.index)
  expect "worker local nesting wins"
    (inner.parentIndex == some worker.index && inner.depth == worker.depth + 1)

end LeanProfiler.Tests.Runtime
