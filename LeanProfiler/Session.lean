/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Output
import Std.Sync.Mutex

/-!
# Profiling sessions

Only one profiling session may use the process-wide capture buffer at a time.
-/

namespace LeanProfiler
namespace Internal

/-- Mutable ownership state for the single process-wide capture buffer. -/
structure SessionState where
  recording : Bool := false
  owned : Bool := false
  deriving Inhabited

initialize sessionState : Std.Mutex SessionState ←
  Std.Mutex.new {}

/-- Whether `span` calls currently belong to an active profiling session. -/
public def profilingIsEnabled : IO Bool :=
  sessionState.atomically do
    return (← get).recording

/-- Claim exclusive session ownership while leaving instrumentation disabled. -/
def acquireSession : IO Bool :=
  sessionState.atomically do
    let state ← get
    if state.owned then
      return false
    set ({ recording := false, owned := true } : SessionState)
    return true

/-- Change span admission after the caller has acquired session ownership. -/
def setRecording (recording : Bool) : IO Unit :=
  sessionState.atomically do
    modify fun state => { state with recording }

/-- Return the capture buffer to its inactive, unowned state. -/
def releaseSession : IO Unit :=
  sessionState.atomically do
    set ({ recording := false, owned := false } : SessionState)

/-- Materialize an `IO.Error` so action and export outcomes can be considered together. -/
def attempt {α : Type} (action : IO α) : IO (Except IO.Error α) :=
  try
    return .ok (← action)
  catch error =>
    return .error error

/-- Best-effort diagnostic for an export error secondary to an application error. -/
def reportSecondaryExportError (error : IO.Error) : IO Unit :=
  try
    IO.eprintln s!"LeanProfiler could not export the failed session: {error}"
  catch _ =>
    pure ()

/-- Apply the documented precedence between application and export errors. -/
def finishActionResult (actionResult : Except IO.Error α)
    (exportResult : Except IO.Error Unit) : IO α :=
  match actionResult, exportResult with
  | .ok value, .ok _ => pure value
  | .ok _, .error exportError => throw exportError
  | .error actionError, .ok _ => throw actionError
  | .error actionError, .error exportError => do
      -- Reporting the secondary failure without replacing the application's original exception
      -- keeps profiling observational when both the workload and artifact writer fail.
      reportSecondaryExportError exportError
      throw actionError

/--
Run one process-level profiling session.

The capture is cleared before recording becomes visible to `span`. Overlapping or nested sessions
are rejected because they would share events and report ownership. The action should also await any
worker tasks whose spans belong to the session before it returns.

If the action fails, LeanProfiler still attempts to write its report. A report failure propagates
when the action succeeded. When both fail, the report failure is printed to standard error and the
action's original `IO.Error` is rethrown.
-/
public def runSession {α : Type} (config : ProfilerConfig) (name : String)
    (make : Unit → IO α) : IO α := do
  unless ← acquireSession do
    throw <| IO.userError "a LeanProfiler session is already active"
  try
    unless config.enabled do
      return ← make ()
    resetCapture config.eventLimit
    -- Clearing while recording is disabled prevents a newly admitted span from being erased by
    -- session setup.
    setRecording true
    let actionResult ← attempt (recordSpan name (make ()))
    setRecording false
    let exportResult ←
      attempt (finishCapture config.tracePath config.summaryPath config.processName)
    finishActionResult actionResult exportResult
  finally
    releaseSession

end Internal

/--
Run one process-level profiling session with an explicit configuration.

Only one session can own the process-wide capture at a time. When profiling is disabled, `action`
runs normally and no artifacts are written.
-/
public def profile {α : Type} (config : ProfilerConfig) (name : String)
    (action : IO α) : IO α :=
  Internal.runSession config name fun _ => action

/--
Run a profiling session using the environment configuration loaded at process startup.
-/
public def profileFromEnvironment {α : Type} (name : String) (action : IO α) : IO α :=
  profile startupConfig name action

end LeanProfiler
