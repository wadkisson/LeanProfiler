/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Analysis.Report
public import LeanProfiler.Config
public import Lean.Data.Json
import LeanProfiler.Analysis.Summary
import LeanProfiler.Output.SummaryJson
import LeanProfiler.Output.Terminal
import LeanProfiler.Output.TraceEvent
import LeanProfiler.Runtime.Capture

/-!
# Artifact export

Export creates parent directories, writes the trace and summary, and prints the terminal report.
Session ownership keeps the same capture from being written twice.
-/

namespace LeanProfiler

/-- Pretty-print JSON to `path`, creating its parent directory when needed. -/
public def writeJsonFile (path : System.FilePath) (value : Lean.Json) : IO Unit := do
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile path (Lean.Json.pretty value ++ "\n")

/-- Write the Perfetto trace with an optional process-track label. -/
public def exportTrace (report : Report) (path : System.FilePath)
    (processName : String := ProfilerConfig.defaults.processName) : IO Unit :=
  writeJsonFile path (traceJson report processName)

/-- Write the detailed nanosecond summary. -/
public def exportSummary (report : Report) (path : System.FilePath) : IO Unit :=
  writeJsonFile path (summaryJson report)

namespace Internal

/--
Analyze the current capture, write both artifacts, and print the terminal report at most once.

If writing either file fails, the report claim is released so a caller can retry with another path.
-/
public def finishCapture (tracePath summaryPath : System.FilePath)
    (processName : String := ProfilerConfig.defaults.processName) : IO Unit := do
  unless ← claimReport do
    return
  try
    let status ← captureStatus
    let report := {
      analyze (← capturedEvents) with
      process := status.process
      eventLimit := status.eventLimit
      droppedEvents := status.droppedEvents
    }
    exportTrace report tracePath processName
    exportSummary report summaryPath
    printSummary report
    IO.println s!"Trace: {tracePath} (open with https://ui.perfetto.dev)"
    IO.println s!"Summary: {summaryPath}"
  catch error =>
    releaseReportClaim
    throw error

end Internal
end LeanProfiler
