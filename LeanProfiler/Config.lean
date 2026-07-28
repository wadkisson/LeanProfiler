/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import Std

/-!
# Profiler configuration

Construct `ProfilerConfig` directly or read LeanProfiler's environment variables with
`ProfilerConfig.fromEnvironment`.
-/

namespace LeanProfiler

/--
Names of the environment variables used to configure a profiling process. Applications may replace
them when they use a different environment contract.
-/
public structure ProfilerEnvironment where
  enabled : String := "LEAN_PROFILE"
  tracePath : String := "LEAN_PROFILE_OUT"
  summaryPath : String := "LEAN_PROFILE_SUMMARY_OUT"
  eventLimit : String := "LEAN_PROFILE_MAX_EVENTS"
  processName : String := "LEAN_PROFILE_PROCESS_NAME"
  deriving Repr, Inhabited, DecidableEq

/--
Settings for one profiling session.

`enabled = false` runs the supplied action without recording spans or writing artifacts.
`eventLimit = none` keeps every completed span. The paths and trace process name are ordinary fields
so an application does not need environment variables to choose them.
-/
public structure ProfilerConfig where
  enabled : Bool := false
  tracePath : System.FilePath := "build/leanprofiler-trace.json"
  summaryPath : System.FilePath := "build/leanprofiler-summary.json"
  eventLimit : Option Nat := none
  processName : String := "Lean process"
  deriving Repr, Inhabited, DecidableEq

/-- Library defaults used when no application or environment override is supplied. -/
public def ProfilerConfig.defaults : ProfilerConfig :=
  {}

/-- Interpret the common false-like spellings accepted by the enable flag. -/
def parseFlag (raw : String) : Bool :=
  let value := raw.trimAscii.toString.toLower
  value != "" && value != "0" && value != "false" && value != "off" && value != "no"

/-- Trim an environment value and reject it when only whitespace remains. -/
def nonemptyValue (raw : String) : Option String :=
  let value := raw.trimAscii.toString
  if value.isEmpty then none else some value

/--
Read a profiler configuration from the process environment.

Missing variables preserve `fallback`. An empty output path or process name also preserves it.
When the event-limit variable is present but is not a natural number, the result is uncapped. The
environment names are configurable so embedding applications can keep their own naming scheme.
-/
public def ProfilerConfig.fromEnvironment
    (fallback : ProfilerConfig := ProfilerConfig.defaults)
    (environment : ProfilerEnvironment := {}) : IO ProfilerConfig := do
  let enabled :=
    match ← IO.getEnv environment.enabled with
    | some raw => parseFlag raw
    | none => fallback.enabled
  let tracePath :=
    match (← IO.getEnv environment.tracePath).bind nonemptyValue with
    | some path => System.FilePath.mk path
    | none => fallback.tracePath
  let summaryPath :=
    match (← IO.getEnv environment.summaryPath).bind nonemptyValue with
    | some path => System.FilePath.mk path
    | none => fallback.summaryPath
  let eventLimit :=
    match ← IO.getEnv environment.eventLimit with
    | some raw => raw.trimAscii.toString.toNat?
    | none => fallback.eventLimit
  let processName :=
    (← IO.getEnv environment.processName).bind nonemptyValue |>.getD fallback.processName
  pure { enabled, tracePath, summaryPath, eventLimit, processName }

/--
Configuration loaded once when the process initializes.

Pass an explicit value to `profile` when settings should come from command-line arguments or an
application configuration file instead.
-/
public initialize startupConfig : ProfilerConfig ←
  ProfilerConfig.fromEnvironment

end LeanProfiler
