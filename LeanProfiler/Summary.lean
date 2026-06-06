module

public import LeanProfiler.Timer
public import Lean

@[expose] public section

def padRight (s : String) (width : Nat) : String :=
  if s.length >= width then s
  else s ++ String.ofList (List.replicate (width - s.length) ' ')

def padLeft (s : String) (width : Nat) : String :=
  if s.length >= width then s
  else String.ofList (List.replicate (width - s.length) ' ') ++ s

def summaryNameWidth : Nat := 56
def flameBarWidth : Nat := 24

def displayName (name : String) (width : Nat := summaryNameWidth) : String :=
  if name.length ≤ width then
    name
  else
    let keep := width - 3
    "..." ++ (name.drop (name.length - keep))

def formatDuration (ns : Nat) : String :=
  if ns < 1000 then s!"{ns} ns"
  else if ns < 1_000_000 then
    let scaled := (ns * 100) / 1000
    s!"{scaled / 100}.{(scaled % 100) / 10}{scaled % 10} µs"
  else if ns < 1_000_000_000 then
    let scaled := (ns * 100) / 1_000_000
    s!"{scaled / 100}.{(scaled % 100) / 10}{scaled % 10} ms"
  else
    let scaled := (ns * 100) / 1_000_000_000
    s!"{scaled / 100}.{(scaled % 100) / 10}{scaled % 10} s"

def flameBar (selfNs totalSelf : Nat) : String :=
  if totalSelf == 0 then
    ""
  else
    let units := (selfNs * flameBarWidth) / totalSelf
    let n := min units flameBarWidth
    String.ofList (List.replicate n '█')

structure SummaryRow where
  name : String
  totalNs : Nat
  selfNs : Nat
  calls : Nat
  pct : Nat
  bar : String

def buildSummaryRows (events : Array ProfileEvent) : Array SummaryRow := Id.run do
  let mut totals : Std.HashMap String (Nat × Nat × Nat) := {}
  for e in events do
    let dur := e.endNs - e.startNs
    let mut childDur := 0
    for c in events do
      if c.depth == e.depth + 1 && c.startNs >= e.startNs && c.endNs <= e.endNs then
        childDur := childDur + (c.endNs - c.startNs)
    let selfDur := dur - childDur
    match totals[e.name]? with
    | none => totals := totals.insert e.name (dur, selfDur, 1)
    | some (t, s, c) => totals := totals.insert e.name (t + dur, s + selfDur, c + 1)
  let rows := totals.toArray.map (fun (k, v) => (k, v.1, v.2.1, v.2.2))
  let sorted := rows.qsort (fun a b => a.2.2.1 > b.2.2.1)
  let totalSelf := sorted.foldl (init := 0) (fun acc r => acc + r.2.2.1)
  sorted.map fun (name, total, self, calls) =>
    let pct := if totalSelf == 0 then 0 else (self * 1000) / totalSelf
    { name, totalNs := total, selfNs := self, calls, pct, bar := flameBar self totalSelf }

def defaultTracePath : System.FilePath := "build/leanprofiler-trace.json"

def printSummary : IO Unit := do
  let events ← getEvents
  let rows := buildSummaryRows events
  let w := summaryNameWidth
  let rule := String.ofList (List.replicate w '-')
  IO.println ""
  IO.println s!"{padRight "Name" w} {padLeft "Self" 12} {padLeft "Total" 12} {padLeft "Calls" 8} {padLeft "%" 7} Flame"
  IO.println s!"{rule} ------------ ------------ -------- ------- {String.ofList (List.replicate flameBarWidth '-')}"
  for r in rows do
    let pctStr := s!"{r.pct / 10}.{r.pct % 10}%"
    IO.println s!"{padRight (displayName r.name w) w} {padLeft (formatDuration r.selfNs) 12} {padLeft (formatDuration r.totalNs) 12} {padLeft (toString r.calls) 8} {padLeft pctStr 7} {r.bar}"

/-- Perfetto / Chrome trace JSON — open at https://ui.perfetto.dev for a flame timeline. -/
def exportFlameGraph (path : System.FilePath) : IO Unit := do
  if let some dir := path.parent then
    IO.FS.createDirAll dir
  let events ← getEvents
  let q := "\""
  let eventStrs := events.map fun e =>
    let dur := e.endNs - e.startNs
    s!"\{{q}name{q}:{q}{e.name}{q},{q}cat{q}:{q}lean{q},{q}ph{q}:{q}X{q},{q}ts{q}:{e.startNs},{q}dur{q}:{dur},{q}pid{q}:1,{q}tid{q}:1}"
  let joined := String.intercalate ",\n  " eventStrs.toList
  let json := s!"\{{q}displayTimeUnit{q}:{q}ns{q},{q}traceEvents{q}:[\n  {joined}\n]}"
  IO.FS.writeFile path json

/-- Run `action`, then write a Perfetto trace and print the text summary. -/
def withSummary (action : IO α) : IO α := do
  try
    action
  finally
    exportFlameGraph defaultTracePath
    printSummary
    IO.println s!"Flame trace: {defaultTracePath} → https://ui.perfetto.dev"
