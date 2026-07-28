/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Analysis.Report

/-!
# Terminal reports

Terminal output gives a quick capture overview and ranks grouped rows by exclusive time.
-/

namespace LeanProfiler

def fitRight (text : String) (width : Nat) : String :=
  if text.length > width then
    if width == 0 then ""
    else String.ofList (text.toList.take (width - 1)) ++ "…"
  else
    text ++ String.ofList (List.replicate (width - text.length) ' ')

def padLeft (text : String) (width : Nat) : String :=
  if text.length ≥ width then text
  else String.ofList (List.replicate (width - text.length) ' ') ++ text

/-- Human-readable duration truncated to two decimal places above one microsecond. -/
public def formatDuration (ns : Nat) : String :=
  if ns < 1000 then
    s!"{ns} ns"
  else if ns < 1_000_000 then
    let scaled := (ns * 100) / 1000
    s!"{scaled / 100}.{(scaled % 100) / 10}{scaled % 10} us"
  else if ns < 1_000_000_000 then
    let scaled := (ns * 100) / 1_000_000
    s!"{scaled / 100}.{(scaled % 100) / 10}{scaled % 10} ms"
  else
    let scaled := (ns * 100) / 1_000_000_000
    s!"{scaled / 100}.{(scaled % 100) / 10}{scaled % 10} s"

/-- Print capture metadata, validation problems, and rows ranked by exclusive time. -/
public def printSummary (report : Report) : IO Unit := do
  IO.println ""
  IO.println (s!"Lean profile: {report.events.size} events, {report.threadCount} threads, "
    ++ s!"window {formatDuration report.traceWindowNs}, "
    ++ s!"recorded thread time {formatDuration report.recordedThreadNs}, "
    ++ s!"{report.recordedHeartbeats} Lean heartbeats")
  if let some process := report.process then
    IO.println (s!"Process resources: user CPU {process.userCpuMs} ms, "
      ++ s!"system CPU {process.systemCpuMs} ms, peak RSS "
      ++ s!"{process.peakResidentSetSizeKb} KiB, context switches "
      ++ s!"{process.voluntaryContextSwitches + process.involuntaryContextSwitches}")
  if report.droppedEvents != 0 then
    IO.println (s!"Capture limit: dropped {report.droppedEvents} span(s) after retaining "
      ++ s!"{report.events.size}")
  if !report.issues.isEmpty then
    IO.println s!"Validation: {report.issues.size} issue(s)"
    for problem in report.issues do
      let location := (problem.eventIndex.map fun index => s!"event {index}: ").getD ""
      IO.println s!"  {location}{problem.message}"
  let nameWidth := 40
  let rule := String.ofList (List.replicate nameWidth '-')
  IO.println (s!"{fitRight "Name" nameWidth} {padLeft "Self" 12} {padLeft "Total" 12} "
    ++ s!"{padLeft "Calls" 8} {padLeft "Mean" 12} {padLeft "P95" 12} "
    ++ s!"{padLeft "Self HB" 12} {padLeft "%" 7}")
  IO.println (s!"{rule} ------------ ------------ -------- ------------ ------------ "
    ++ s!"------------ -------")
  for row in report.rows do
    let pct := s!"{row.sharePermille / 10}.{row.sharePermille % 10}%"
    IO.println (s!"{fitRight row.key.label nameWidth} {padLeft (formatDuration row.selfNs) 12} "
      ++ s!"{padLeft (formatDuration row.totalNs) 12} {padLeft (toString row.calls) 8} "
      ++ s!"{padLeft (formatDuration row.meanNs) 12} {padLeft (formatDuration row.p95Ns) 12} "
      ++ s!"{padLeft (toString row.selfHeartbeats) 12} {padLeft pct 7}")

end LeanProfiler
