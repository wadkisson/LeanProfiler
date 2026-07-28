/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import LeanProfiler
import LeanProfiler.Syntax
import LeanProfiler.Tests.Support

/-!
# Application instrumentation tests

Exercises the instrumentation API through the same umbrella import used by applications. The
enabled-session test reads its saved summary back, so API changes that still compile but stop
carrying context into reports are caught as well.
-/

namespace LeanProfiler.Tests.Instrumentation

open LeanProfiler

abbrev expect := LeanProfiler.Tests.expect "instrumentation"

def artifactConfig : ProfilerConfig :=
  {
    enabled := true
    tracePath := "build/test-artifacts/instrumentation-trace.json"
    summaryPath := "build/test-artifacts/instrumentation-summary.json"
    processName := "LeanProfiler instrumentation test"
  }

/-- A representative declaration using the command-level instrumentation syntax. -/
profiled def profiledSuccessor (value : Nat) : IO Nat :=
  pure (value + 1)

/--
Construct an action while recording the span index visible at construction time.

`unsafeIO` is intentionally confined to this test probe. An ordinary `IO` effect cannot distinguish
building an action from running it, while this regression needs to catch macro expansions that build
the declaration body before reserving its generated span.
-/
@[noinline] unsafe def observeActionConstruction (observed : IO.Ref (Option Nat)) : IO Unit :=
  match unsafeIO do observed.set (← currentSpanIndex) with
  | .ok _ => pure ()
  | .error error => throw error

/-- A profiled declaration whose action constructor records the generated span boundary. -/
unsafe profiled def profiledConstructionProbe (observed : IO.Ref (Option Nat)) : IO Unit :=
  observeActionConstruction observed

namespace ProfiledEntryPoint

/--
Compile the special `main` expansion without starting another process-wide session during tests.
-/
profiled def main : IO Unit :=
  pure ()

end ProfiledEntryPoint

def environmentProfileAction : IO Nat :=
  profileFromEnvironment "instrumentation.environment" (pure 41)

/-- Run application-level instrumentation and artifact compatibility checks. -/
public unsafe def run : IO Unit := do
  let disabledRuns ← IO.mkRef 0
  let disabledResult ←
    profile ({ enabled := false } : ProfilerConfig) "instrumentation.disabled" do
      span "instrumentation.disabled-span" do
        disabledRuns.modify (· + 1)
        pure 17
  expect "a disabled profile returns the action result" (disabledResult == 17)
  expect "a disabled span still runs its action exactly once" ((← disabledRuns.get) == 1)

  let constructionIndex ← IO.mkRef none
  let (profiledResult, outerIndex) ←
    profile artifactConfig "instrumentation.session" do
      let outerIndex ← currentSpanIndex
      let successor ← profiledSuccessor 20
      profiledConstructionProbe constructionIndex
      let contextualIndex ←
        withContext
            (metadata := {
              activity := some "host"
              backend := some "eager"
              dtype := some "float32"
              device := some "cpu"
            })
            (action :=
              withStep 7 <|
                withModule "encoder.block.0" <|
                  withPhase "forward" <|
                    match outerIndex with
                    | some parent =>
                        withParentIndex parent <|
                          span "instrumentation.linear" currentSpanIndex
                            (metadata := { backend := some "compiled" })
                    | none =>
                        span "instrumentation.linear" currentSpanIndex
                          (metadata := { backend := some "compiled" }))
      expect "nested span exposes its index" contextualIndex.isSome
      pure (successor, outerIndex)
  expect "profile returns its action result" (profiledResult == 21)
  expect "the session wrapper has an active span" outerIndex.isSome
  let generatedIndex ← constructionIndex.get
  expect "a profiled declaration constructs its action under its own span"
    (generatedIndex.isSome && generatedIndex != outerIndex)

  let artifact ← readSummaryArtifact artifactConfig.summaryPath
  let contextualRow? :=
    artifact.rows.find? fun row => row.key.name == "instrumentation.linear"
  expect "context helpers reach the saved report" <|
    contextualRow?.any fun row =>
      row.key.phase == some "forward" &&
        row.key.activity == some "host" &&
        row.key.backend == some "compiled" &&
        row.key.dtype == some "float32" &&
        row.key.device == some "cpu" &&
        row.key.moduleName == some "encoder.block.0"
  expect "profiled declarations appear in the saved report" <|
    artifact.rows.any fun row => row.key.name == "profiledSuccessor"

  let comparison := compareRows
    { metric := .p95Ns, threshold := {} }
    artifact.rows artifact.rows
  expect "a saved report can feed the comparison API"
    (comparison.matched.size == artifact.rows.size &&
      comparison.missing.isEmpty &&
      comparison.newRows.isEmpty &&
      !comparison.hasRegression)

  -- The startup configuration is process-global. Running this branch only for the default disabled
  -- setting keeps the test independent of a caller's chosen artifact paths.
  unless startupConfig.enabled do
    expect "the environment entry point returns its action result"
      ((← environmentProfileAction) == 41)

end LeanProfiler.Tests.Instrumentation
