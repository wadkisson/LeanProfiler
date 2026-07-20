/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
-/

module

public import Std.Sync

/-!
# LeanProfiler Runtime

Tiny host-side span profiler for compiled Lean programs: record nested spans, print a terminal
summary, and optionally write a Chrome/Perfetto JSON trace.
-/

@[expose] public section

namespace LeanProfiler

/-- One timed span. Times are monotonic nanoseconds. -/
structure Event where
  name : String
  startNs : Nat
  endNs : Nat
  depth : Nat
  index : Nat
  parentIndex : Option Nat := none
  threadId : UInt64 := 0
  deriving Repr, Inhabited

def Event.durationNs (event : Event) : Nat :=
  event.endNs - event.startNs

structure ProfilerState where
  events : Array Event := #[]
  ended : Bool := false
  seq : Nat := 0
  stacks : Std.HashMap UInt64 (Array Nat) := {}
  deriving Repr, Inhabited

initialize profilerState : Std.Mutex ProfilerState ← Std.Mutex.new {}

structure SpanReservation where
  depth : Nat
  index : Nat
  parentIndex : Option Nat
  threadId : UInt64
  deriving Repr

/-- Reserve a span slot on this thread's stack. -/
def reserveSpan : IO SpanReservation := do
  let tid ← IO.getTID
  profilerState.atomically do
    let state ← get
    let stack := state.stacks.getD tid #[]
    let parentIndex := stack.back?
    let depth := stack.size
    let index := state.seq
    set { state with
      seq := state.seq + 1
      stacks := state.stacks.insert tid (stack.push index) }
    pure { depth, index, parentIndex, threadId := tid }

/-- Push a completed event and pop its stack frame. -/
def completeSpan (event : Event) : IO Unit := do
  let tid := event.threadId
  profilerState.atomically do
    let state ← get
    let stack := state.stacks.getD tid #[]
    let stack :=
      match stack.back? with
      | some top =>
          if top == event.index then stack.pop
          else stack.filter (fun index => index != event.index)
      | none => stack
    set { state with
      stacks := state.stacks.insert tid stack
      events := state.events.push event }

/-- Time an `IO` action as a named span. -/
def recordSpan {α : Type} (name : String) (action : IO α) : IO α := do
  let start ← IO.monoNanosNow
  let reservation ← reserveSpan
  try
    action
  finally
    let stop ← IO.monoNanosNow
    completeSpan {
      name := name
      startNs := start
      endNs := stop
      depth := reservation.depth
      index := reservation.index
      parentIndex := reservation.parentIndex
      threadId := reservation.threadId
    }

def getEvents : IO (Array Event) :=
  profilerState.atomically do
    let state ← get
    pure state.events

def clear : IO Unit := do
  profilerState.atomically do
    set ({} : ProfilerState)

/-! ## Terminal summary -/

def padRight (s : String) (width : Nat) : String :=
  if s.length >= width then s
  else s ++ String.ofList (List.replicate (width - s.length) ' ')

def padLeft (s : String) (width : Nat) : String :=
  if s.length >= width then s
  else String.ofList (List.replicate (width - s.length) ' ') ++ s

def summaryNameWidth : Nat := 40
def flameBarWidth : Nat := 24

def formatDuration (ns : Nat) : String :=
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

def flameBar (selfNs totalSelf : Nat) : String :=
  if totalSelf == 0 then ""
  else
    let n := min ((selfNs * flameBarWidth) / totalSelf) flameBarWidth
    String.ofList (List.replicate n '#')

structure SummaryRow where
  name : String
  totalNs : Nat
  selfNs : Nat
  calls : Nat
  pct : Nat
  bar : String

/-- Sum immediate child durations keyed by parent event index. -/
def childDurationsByIndex (events : Array Event) : Std.HashMap Nat Nat := Id.run do
  let mut childDurations : Std.HashMap Nat Nat := {}
  for event in events do
    match event.parentIndex with
    | some parent =>
        childDurations :=
          childDurations.insert parent (childDurations.getD parent 0 + event.durationNs)
    | none => pure ()
  childDurations

/-- Group events by name and rank by self-time. -/
def buildSummaryRows (events : Array Event) : Array SummaryRow := Id.run do
  let childDurations := childDurationsByIndex events
  let mut totals : Std.HashMap String (Nat × Nat × Nat) := {}
  for e in events do
    let dur := e.durationNs
    let selfDur := dur - childDurations.getD e.index 0
    match totals[e.name]? with
    | none => totals := totals.insert e.name (dur, selfDur, 1)
    | some (t, s, c) => totals := totals.insert e.name (t + dur, s + selfDur, c + 1)
  let rows := totals.toArray.map (fun (k, v) => (k, v.1, v.2.1, v.2.2))
  let sorted := rows.qsort (fun a b => a.2.2.1 > b.2.2.1)
  let totalSelf := sorted.foldl (init := 0) (fun acc r => acc + r.2.2.1)
  sorted.map fun (name, total, self, calls) =>
    let pct := if totalSelf == 0 then 0 else (self * 1000) / totalSelf
    { name, totalNs := total, selfNs := self, calls, pct, bar := flameBar self totalSelf }

def printSummary : IO Unit := do
  let rows := buildSummaryRows (← getEvents)
  let w := summaryNameWidth
  let rule := String.ofList (List.replicate w '-')
  IO.println ""
  IO.println s!"{padRight "Name" w} {padLeft "Self" 12} {padLeft "Total" 12} {padLeft "Calls" 8} {padLeft "%" 7} Flame"
  IO.println s!"{rule} ------------ ------------ -------- ------- {String.ofList (List.replicate flameBarWidth '-')}"
  for r in rows do
    let pctStr := s!"{r.pct / 10}.{r.pct % 10}%"
    IO.println s!"{padRight r.name w} {padLeft (formatDuration r.selfNs) 12} {padLeft (formatDuration r.totalNs) 12} {padLeft (toString r.calls) 8} {padLeft pctStr 7} {r.bar}"

/-! ## Chrome / Perfetto trace -/

def jsonEscape (s : String) : String :=
  let escapeChar (c : Char) : String :=
    if c = '"' then "\\\""
    else if c = '\\' then "\\\\"
    else if c = '\n' then "\\n"
    else if c = '\r' then "\\r"
    else if c = '\t' then "\\t"
    else c.toString
  String.join (s.toList.map escapeChar)

/-- Write a Chrome/Perfetto-compatible JSON trace. -/
def exportTrace (path : String) : IO Unit := do
  let path : System.FilePath := path
  if let some dir := path.parent then
    IO.FS.createDirAll dir
  let events ← getEvents
  let q := "\""
  let eventStrs := events.map fun e =>
    s!"\{{q}name{q}:{q}{jsonEscape e.name}{q},{q}cat{q}:{q}lean{q},{q}ph{q}:{q}X{q},{q}ts{q}:{e.startNs},{q}dur{q}:{e.durationNs},{q}pid{q}:1,{q}tid{q}:{e.threadId},{q}args{q}:\{{q}event_index{q}:{e.index},{q}event_depth{q}:{e.depth}}}"
  let json := s!"\{{q}displayTimeUnit{q}:{q}ns{q},{q}traceEvents{q}:[\n  {String.intercalate ",\n  " eventStrs.toList}\n]}"
  IO.FS.writeFile path json

/-- Print the summary and write a Perfetto JSON trace (at most once). -/
def finish (tracePath : String) : IO Unit := do
  let shouldFinish ← profilerState.atomically do
    let state ← get
    if state.ended then
      pure false
    else
      set { state with ended := true }
      pure true
  if shouldFinish then
    exportTrace tracePath
    printSummary
    IO.println s!"Lean profile trace: {tracePath} -> https://ui.perfetto.dev"

end LeanProfiler
