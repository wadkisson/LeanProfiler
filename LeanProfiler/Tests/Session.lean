/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfiler.Instrumentation
import LeanProfiler.Tests.Support

/-!
# Profiling session tests

Checks session ownership, disabled captures, export failures, and cleanup.
-/

namespace LeanProfiler.Tests.Session

open LeanProfiler
open LeanProfiler.Internal

abbrev expect := LeanProfiler.Tests.expect "session"

def captureError (action : IO α) : IO (Option String) :=
  try
    action *> pure none
  catch error =>
    pure (some error.toString)

def artifactConfig (stem : String) : ProfilerConfig :=
  {
    enabled := true
    tracePath := s!"build/test-artifacts/{stem}-trace.json"
    summaryPath := s!"build/test-artifacts/{stem}-summary.json"
    processName := "LeanProfiler session test"
  }

/-- Run session ownership, failure precedence, export, and recovery checks. -/
public def run : IO Unit := do
  expect "recording begins inactive" (!(← profilingIsEnabled))
  resetCapture none
  span "outside-session" (pure ())
  expect "span outside a session is ignored" (← capturedEvents).isEmpty

  profile ({ enabled := false } : ProfilerConfig) "disabled" do
    expect "disabled session stays inactive" (!(← profilingIsEnabled))
    span "disabled-span" (pure ())
  expect "disabled session recorded nothing" (← capturedEvents).isEmpty
  expect "disabled session restored inactive state" (!(← profilingIsEnabled))

  profile (artifactConfig "session-success") "outer" do
    expect "enabled session activates spans" (← profilingIsEnabled)
    let overlap ← captureError <|
      profile ({ enabled := false } : ProfilerConfig) "nested" (pure ())
    expect "nested session is rejected"
      (overlap.any fun message => message.contains "already active")
    span "inner" (pure ())
  let successful ← capturedEvents
  expect "successful session retained wrapper and child"
    (successful.size == 2 && successful[0]!.name == "outer" && successful[1]!.name == "inner")
  expect "successful session restored inactive state" (!(← profilingIsEnabled))

  let actionFailure ← captureError <|
    profile (artifactConfig "session-action-error") "failing-action"
      (throw <| IO.userError "application failure sentinel" : IO Unit)
  expect "action error propagates after successful export"
    (actionFailure.any fun message => message.contains "application failure sentinel")
  expect "exceptional action releases session ownership" (!(← profilingIsEnabled))

  let blocker : System.FilePath := "build/test-artifacts/session-export-blocker"
  if let some parent := blocker.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile blocker "this file intentionally blocks directory creation"
  let exportFailureConfig : ProfilerConfig := {
    enabled := true
    tracePath := blocker / "trace.json"
    summaryPath := blocker / "summary.json"
  }
  let exportFailure ← captureError <|
    profile exportFailureConfig "failing-export" (pure ())
  expect "lone export error propagates" exportFailure.isSome
  expect "export failure releases session ownership" (!(← profilingIsEnabled))

  let combinedFailure ← captureError <|
    profile exportFailureConfig "two-failures"
      (throw <| IO.userError "original action failure" : IO Unit)
  expect "action error wins when action and export both fail"
    (combinedFailure.any fun message => message.contains "original action failure")
  expect "combined failure restores inactive state" (!(← profilingIsEnabled))

  profile (artifactConfig "session-recovery") "recovery" do
    span "after-errors" (pure ())
  expect "a later session can acquire ownership"
    ((← capturedEvents).any fun event => event.name == "after-errors")

end LeanProfiler.Tests.Session
