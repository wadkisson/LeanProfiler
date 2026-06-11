/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
-/

module

public import Lean
public import Std.Sync

/-!
# LeanProfiler Runtime

Reusable runtime profiler for executable Lean programs.

The library owns the generic pieces: structured span events, nesting, runtime context, grouped
terminal summaries, Chrome/Perfetto JSON, and a self-contained HTML report. Downstream projects
should add only domain-specific adapters, such as CUDA synchronization or tensor shape metadata.
-/

@[expose] public section

namespace LeanProfiler

/-! ## Event Model -/

/-- Structured metadata attached to a runtime profiler event. -/
structure Metadata where
  phase : Option String := none
  backend : Option String := none
  dtype : Option String := none
  device : Option String := none
  timing : Option String := none
  moduleName : Option String := none
  graphNode : Option String := none
  stepIndex : Option Nat := none
  inputShapes : Array String := #[]
  outputShape : Option String := none
  allocBytes : Option Nat := none
  allocLiveBytes : Option Nat := none
  allocPeakBytes : Option Nat := none
  allocDeltaBytes : Option Int := none
  deriving Repr, Inhabited

structure Context where
  stepIndex : Option Nat := none
  moduleName : Option String := none
  parentIndex : Option Nat := none
  deriving Repr, Inhabited

/-- One runtime span. Times are monotonic nanoseconds. -/
structure Event where
  name : String
  startNs : Nat
  endNs : Nat
  depth : Nat
  index : Nat
  parentIndex : Option Nat := none
  threadId : UInt64 := 0
  metadata : Metadata := {}
  deriving Repr, Inhabited

def Event.durationNs (event : Event) : Nat :=
  event.endNs - event.startNs

structure ProfilerState where
  events : Array Event := #[]
  ended : Bool := false
  seq : Nat := 0
  stacks : Std.HashMap UInt64 (Array Nat) := {}
  contexts : Std.HashMap UInt64 Context := {}
  eventDepths : Std.HashMap Nat Nat := {}
  deriving Repr, Inhabited

initialize profilerState : Std.Mutex ProfilerState ← Std.Mutex.new {}

/-! ## Runtime Context -/

def Metadata.withContext (metadata : Metadata) (ctx : Context) : Metadata :=
  { metadata with
    stepIndex := metadata.stepIndex <|> ctx.stepIndex
    moduleName := metadata.moduleName <|> ctx.moduleName }

structure SpanReservation where
  depth : Nat
  index : Nat
  parentIndex : Option Nat
  threadId : UInt64
  context : Context
  deriving Repr

def reserveSpan : IO SpanReservation := do
  let tid ← IO.getTID
  profilerState.atomically do
    let state ← get
    let stack := state.stacks.getD tid #[]
    let ctx := state.contexts.getD tid {}
    let parentIndex := ctx.parentIndex <|> stack.back?
    let depth :=
      match parentIndex with
      | some parent => (state.eventDepths.getD parent (stack.size - 1)) + 1
      | none => stack.size
    let index := state.seq
    set { state with
      seq := state.seq + 1
      stacks := state.stacks.insert tid (stack.push index)
      eventDepths := state.eventDepths.insert index depth }
    pure { depth, index, parentIndex, threadId := tid, context := ctx }

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

/--
Run an action under extra profiler context.

This is how the report learns that a low-level op belongs to a training step or a model/module.
The context is dynamically scoped with `try/finally`, so a failed operation does not poison later
events.
-/
def withContext {α : Type} (ctx : Context) (action : IO α) : IO α := do
  let tid ← IO.getTID
  let old ← profilerState.atomically do
    let state ← get
    let old := state.contexts.getD tid {}
    set { state with
      contexts := state.contexts.insert tid
        { stepIndex := ctx.stepIndex <|> old.stepIndex
          moduleName := ctx.moduleName <|> old.moduleName
          parentIndex := ctx.parentIndex <|> old.parentIndex } }
    pure old
  try
    action
  finally
    profilerState.atomically do
      let state ← get
      set { state with contexts := state.contexts.insert tid old }

def withStep {α : Type} (step : Nat) (action : IO α) : IO α :=
  withContext { stepIndex := some step } action

def withModule {α : Type} (name : String) (action : IO α) : IO α :=
  withContext { moduleName := some name } action

def withParentIndex {α : Type} (parentIndex : Nat) (action : IO α) : IO α :=
  withContext { parentIndex := some parentIndex } action

def currentSpanIndex : IO (Option Nat) := do
  let tid ← IO.getTID
  profilerState.atomically do
    let state ← get
    pure (state.stacks.getD tid #[]).back?

/-! ## Recording Spans -/

structure SpanHooks where
  before : IO Unit := pure ()
  after : Metadata → IO Metadata := fun metadata => pure metadata

/--
Record a span with extension hooks.

The core profiler only measures host-side wall time. Downstream adapters can use `before` and
`after` to add device synchronization, allocator snapshots, or other runtime metadata without
forking the generic profiler.
-/
def recordSpanWithHooks {α : Type}
    (name : String) (metadata : Metadata := {}) (hooks : SpanHooks := {}) (action : IO α) : IO α := do
  hooks.before
  let start ← IO.monoNanosNow
  let reservation ← reserveSpan
  try
    action
  finally
    let finalMetadata ←
      try
        hooks.after metadata
      catch _ =>
        pure metadata
    let stop ← IO.monoNanosNow
    let event : Event :=
      { name := name
        startNs := start
        endNs := stop
        depth := reservation.depth
        index := reservation.index
        parentIndex := reservation.parentIndex
        threadId := reservation.threadId
        metadata := finalMetadata.withContext reservation.context }
    completeSpan event

/--
Record a host-side span.

Library users decide whether to call this directly or gate it behind their own runtime option. The
span records nesting depth and a stable event index so summaries and timelines can keep their views
consistent.
-/
def recordSpanWith {α : Type} (name : String) (metadata : Metadata := {}) (action : IO α) : IO α := do
  recordSpanWithHooks name metadata {} action

def recordSpan {α : Type} (name : String) (action : IO α) : IO α :=
  recordSpanWith name {} action

def getEvents : IO (Array Event) :=
  profilerState.atomically do
    let state ← get
    pure state.events

def clear : IO Unit := do
  profilerState.atomically do
    set ({} : ProfilerState)

/-! ## Formatting and Terminal Summary -/

def padRight (s : String) (width : Nat) : String :=
  if s.length >= width then
    s
  else
    s ++ String.ofList (List.replicate (width - s.length) ' ')

def padLeft (s : String) (width : Nat) : String :=
  if s.length >= width then
    s
  else
    String.ofList (List.replicate (width - s.length) ' ') ++ s

def summaryNameWidth : Nat := 56
def flameBarWidth : Nat := 24

def displayName (name : String) (width : Nat := summaryNameWidth) : String :=
  if name.length ≤ width then
    name
  else
    let keep := width - 3
    "..." ++ name.drop (name.length - keep)

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
  if totalSelf == 0 then
    ""
  else
    let units := (selfNs * flameBarWidth) / totalSelf
    let n := min units flameBarWidth
    String.ofList (List.replicate n '#')

structure SummaryRow where
  name : String
  totalNs : Nat
  selfNs : Nat
  calls : Nat
  pct : Nat
  bar : String

def Metadata.labelParts (metadata : Metadata) : List String :=
  [metadata.phase, metadata.backend, metadata.dtype, metadata.device, metadata.moduleName].filterMap id

def Event.summaryKey (event : Event) : String :=
  match event.metadata.labelParts with
  | [] => event.name
  | parts => s!"{String.intercalate "/" parts}:{event.name}"

def eventStartLt (a b : Event) : Bool :=
  a.startNs < b.startNs || (a.startNs == b.startNs && a.index < b.index)

/--
Compute immediate child duration per parent event.

Events recorded by this runtime carry an explicit `parentIndex`, so the common path is linear in the
number of events. The stack fallback keeps hand-built legacy events useful in tests and notebooks.
-/
def childDurationsByIndex (events : Array Event) : Std.HashMap Nat Nat := Id.run do
  let hasExplicitParents := events.any (fun event => event.parentIndex.isSome)
  if hasExplicitParents then
    let mut childDurations : Std.HashMap Nat Nat := {}
    for event in events do
      match event.parentIndex with
      | some parent =>
          let old := childDurations.getD parent 0
          childDurations := childDurations.insert parent (old + event.durationNs)
      | none => pure ()
    return childDurations
  let sorted := events.qsort eventStartLt
  let mut stack : Array Event := #[]
  let mut childDurations : Std.HashMap Nat Nat := {}
  for event in sorted do
    while !stack.isEmpty && stack.back!.endNs <= event.startNs do
      stack := stack.pop
    match stack.back? with
    | some parent =>
        if event.depth == parent.depth + 1 && event.endNs <= parent.endNs then
          let old := childDurations.getD parent.index 0
          childDurations := childDurations.insert parent.index (old + event.durationNs)
    | none => pure ()
    stack := stack.push event
  childDurations

/--
Build grouped summary rows for the terminal table.

The grouping key is intentionally human-readable:
`phase/backend/device/module:name`. That makes copied terminal output useful in an issue or PR
without requiring the JSON trace.
-/
def buildSummaryRows (events : Array Event) : Array SummaryRow := Id.run do
  let childDurations := childDurationsByIndex events
  let mut totals : Std.HashMap String (Nat × Nat × Nat) := {}
  for e in events do
    let dur := e.durationNs
    let childDur := childDurations.getD e.index 0
    let selfDur := dur - childDur
    let key := e.summaryKey
    match totals[key]? with
    | none => totals := totals.insert key (dur, selfDur, 1)
    | some (t, s, c) => totals := totals.insert key (t + dur, s + selfDur, c + 1)
  let rows := totals.toArray.map (fun (k, v) => (k, v.1, v.2.1, v.2.2))
  let sorted := rows.qsort (fun a b => a.2.2.1 > b.2.2.1)
  let totalSelf := sorted.foldl (init := 0) (fun acc r => acc + r.2.2.1)
  sorted.map fun (name, total, self, calls) =>
    let pct := if totalSelf == 0 then 0 else (self * 1000) / totalSelf
    { name, totalNs := total, selfNs := self, calls, pct, bar := flameBar self totalSelf }

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

/-! ## Chrome/Perfetto Trace Export -/

def jsonEscape (s : String) : String :=
  let escapeChar (c : Char) : String :=
    if c = '"' then "\\\""
    else if c = '\\' then "\\\\"
    else if c = '\n' then "\\n"
    else if c = '\r' then "\\r"
    else if c = '\t' then "\\t"
    else c.toString
  String.join (s.toList.map escapeChar)

def jsonStringField (key value : String) : String :=
  let q := "\""
  s!"{q}{jsonEscape key}{q}:{q}{jsonEscape value}{q}"

def jsonNatField (key : String) (value : Nat) : String :=
  let q := "\""
  s!"{q}{jsonEscape key}{q}:{value}"

def jsonIntField (key : String) (value : Int) : String :=
  let q := "\""
  s!"{q}{jsonEscape key}{q}:{value}"

def jsonStringArrayField (key : String) (values : Array String) : String :=
  let q := "\""
  let items := values.map fun value => s!"{q}{jsonEscape value}{q}"
  s!"{q}{jsonEscape key}{q}:[{String.intercalate "," items.toList}]"

def Metadata.toTraceArgs (metadata : Metadata) : Array String :=
  let fields := #[]
  let fields := match metadata.phase with | some v => fields.push (jsonStringField "phase" v) | none => fields
  let fields := match metadata.backend with | some v => fields.push (jsonStringField "backend" v) | none => fields
  let fields := match metadata.dtype with | some v => fields.push (jsonStringField "dtype" v) | none => fields
  let fields := match metadata.device with | some v => fields.push (jsonStringField "device" v) | none => fields
  let fields := match metadata.timing with | some v => fields.push (jsonStringField "timing" v) | none => fields
  let fields := match metadata.moduleName with | some v => fields.push (jsonStringField "module" v) | none => fields
  let fields := match metadata.graphNode with | some v => fields.push (jsonStringField "graph_node" v) | none => fields
  let fields := match metadata.stepIndex with | some v => fields.push (jsonNatField "step" v) | none => fields
  let fields :=
    if metadata.inputShapes.isEmpty then fields
    else fields.push (jsonStringArrayField "input_shapes" metadata.inputShapes)
  let fields := match metadata.outputShape with | some v => fields.push (jsonStringField "output_shape" v) | none => fields
  let fields := match metadata.allocBytes with | some v => fields.push (jsonNatField "alloc_bytes" v) | none => fields
  let fields := match metadata.allocLiveBytes with | some v => fields.push (jsonNatField "alloc_live_bytes" v) | none => fields
  let fields := match metadata.allocPeakBytes with | some v => fields.push (jsonNatField "alloc_peak_bytes" v) | none => fields
  match metadata.allocDeltaBytes with
  | some v => fields.push (jsonIntField "alloc_delta_bytes" v)
  | none => fields

def Event.traceCategory (event : Event) : String :=
  match event.metadata.phase with
  | some phase => phase
  | none => "lean"

/--
Export a Chrome/Perfetto trace JSON file.

This is the interoperability path: the JSON is intentionally small and conventional enough to open
in Perfetto or Chrome trace viewers. The trace is an observation artifact, not a proof artifact.
-/
def exportTrace (path : String) : IO Unit := do
  let path : System.FilePath := path
  if let some dir := path.parent then
    IO.FS.createDirAll dir
  let events ← getEvents
  let q := "\""
  let eventStrs := events.map fun e =>
    let dur := e.endNs - e.startNs
    let argsJson := String.intercalate "," e.metadata.toTraceArgs.toList
    let parentJson :=
      match e.parentIndex with
      | some parent => s!",{q}event_parent{q}:{parent}"
      | none => ""
    s!"\{{q}name{q}:{q}{jsonEscape e.name}{q},{q}cat{q}:{q}{jsonEscape e.traceCategory}{q},{q}ph{q}:{q}X{q},{q}ts{q}:{e.startNs},{q}dur{q}:{dur},{q}pid{q}:1,{q}tid{q}:{e.threadId},{q}args{q}:\{{q}event_index{q}:{e.index},{q}event_depth{q}:{e.depth}{parentJson}{if argsJson.isEmpty then "" else "," ++ argsJson}}}"
  let joined := String.intercalate ",\n  " eventStrs.toList
  let json := s!"\{{q}displayTimeUnit{q}:{q}ns{q},{q}traceEvents{q}:[\n  {joined}\n]}"
  IO.FS.writeFile path json

/-! ## HTML Report Data -/

def htmlEscape (s : String) : String :=
  let escapeChar (c : Char) : String :=
    if c = '&' then "&amp;"
    else if c = '<' then "&lt;"
    else if c = '>' then "&gt;"
    else if c = '"' then "&quot;"
    else c.toString
  String.join (s.toList.map escapeChar)

def reportPathForTrace (tracePath : String) : String :=
  tracePath ++ ".html"

def Metadata.phaseName (metadata : Metadata) : String :=
  metadata.phase.getD "other"

def Metadata.deviceName (metadata : Metadata) : String :=
  metadata.device.getD "unknown"

def Metadata.shapeLabel (metadata : Metadata) : String :=
  match metadata.outputShape with
  | some out =>
      if metadata.inputShapes.isEmpty then out
      else s!"{String.intercalate " x " metadata.inputShapes.toList} -> {out}"
  | none =>
      if metadata.inputShapes.isEmpty then "-"
      else String.intercalate " x " metadata.inputShapes.toList

def phaseTotals (events : Array Event) : Array (String × Nat) := Id.run do
  let mut totals : Std.HashMap String Nat := {}
  for e in events do
    let phase := e.metadata.phaseName
    let prev := totals.getD phase 0
    totals := totals.insert phase (prev + e.durationNs)
  totals.toArray.qsort (fun a b => a.2 > b.2)

def shapeTotals (events : Array Event) : Array (String × Nat × Nat) := Id.run do
  let mut totals : Std.HashMap String (Nat × Nat) := {}
  for e in events do
    let label := e.metadata.shapeLabel
    if label != "-" then
      match totals[label]? with
      | none => totals := totals.insert label (e.durationNs, 1)
      | some (t, c) => totals := totals.insert label (t + e.durationNs, c + 1)
  let rows := totals.toArray.map fun (k, v) => (k, v.1, v.2)
  rows.qsort (fun a b => a.2.1 > b.2.1)

def moduleTotals (events : Array Event) : Array (String × Nat × Nat × Nat) := Id.run do
  let mut totals : Std.HashMap String (Nat × Nat × Nat) := {}
  for e in events do
    match e.metadata.moduleName with
    | none => pure ()
    | some name =>
        let peak := e.metadata.allocPeakBytes.getD 0
        match totals[name]? with
        | none => totals := totals.insert name (e.durationNs, 1, peak)
        | some (t, c, p) => totals := totals.insert name (t + e.durationNs, c + 1, max p peak)
  let rows := totals.toArray.map fun (k, v) => (k, v.1, v.2.1, v.2.2)
  rows.qsort (fun a b => a.2.1 > b.2.1)

def stepTotals (events : Array Event) : Array (Nat × Nat × Nat) := Id.run do
  let mut totals : Std.HashMap Nat (Nat × Nat) := {}
  for e in events do
    match e.metadata.stepIndex with
    | none => pure ()
    | some step =>
        match totals[step]? with
        | none => totals := totals.insert step (e.durationNs, 1)
        | some (t, c) => totals := totals.insert step (t + e.durationNs, c + 1)
  let rows := totals.toArray.map fun (k, v) => (k, v.1, v.2)
  rows.qsort (fun a b => a.1 < b.1)

def maxPeakBytes (events : Array Event) : Nat :=
  events.foldl (init := 0) fun acc e =>
    match e.metadata.allocPeakBytes with
    | some n => max acc n
    | none => acc

def allocDeltaMagnitude (event : Event) : Nat :=
  match event.metadata.allocDeltaBytes with
  | none => 0
  | some d =>
      if d < 0 then Int.toNat (-d) else Int.toNat d

structure GroupRow where
  name : String
  totalNs : Nat
  calls : Nat
  peakBytes : Nat
  churnBytes : Nat

def groupRowsBy (events : Array Event) (keyOf : Event → String) : Array GroupRow := Id.run do
  let mut totals : Std.HashMap String (Nat × Nat × Nat × Nat) := {}
  for e in events do
    let key := keyOf e
    let peak := e.metadata.allocPeakBytes.getD 0
    let churn := allocDeltaMagnitude e
    match totals[key]? with
    | none => totals := totals.insert key (e.durationNs, 1, peak, churn)
    | some (t, c, p, m) =>
        totals := totals.insert key (t + e.durationNs, c + 1, max p peak, m + churn)
  let rows := totals.toArray.map fun (k, v) =>
    { name := k, totalNs := v.1, calls := v.2.1, peakBytes := v.2.2.1, churnBytes := v.2.2.2 }
  rows.qsort (fun a b => a.totalNs > b.totalNs)

def Event.opName (event : Event) : String :=
  event.metadata.graphNode.getD event.name

def phaseOpRows (events : Array Event) (phase : String) : Array GroupRow :=
  groupRowsBy (events.filter fun e => e.metadata.phaseName == phase) (fun e => e.opName)

def uniqueMetadataValues (events : Array Event) (pick : Metadata → Option String) : Array String := Id.run do
  let mut seen : Std.HashMap String Unit := {}
  for e in events do
    match pick e.metadata with
    | none => pure ()
    | some value =>
        if value != "" then
          seen := seen.insert value ()
  (seen.toArray.map (·.1)).qsort (· < ·)

def filterOptionsHtml (values : Array String) : String :=
  let options := values.map (fun v =>
    s!"<option value=\"{htmlEscape v}\">{htmlEscape v}</option>")
  String.intercalate "\n" options.toList

def phaseColor (phase : String) : String :=
  if phase == "forward" then "#f3a43b"
  else if phase == "backward" then "#67c7d4"
  else if phase == "step" then "#9be26f"
  else "#d6a4ff"

def Event.dataAttrs (event : Event) : String :=
  let phase := event.metadata.phaseName
  let moduleName := event.metadata.moduleName.getD ""
  let device := event.metadata.deviceName
  let op := event.opName
  s!"data-prof-row data-phase=\"{htmlEscape phase}\" data-module=\"{htmlEscape moduleName}\" data-device=\"{htmlEscape device}\" data-op=\"{htmlEscape op}\""

/-! ## HTML Report Rendering -/

def traceStartNs (events : Array Event) : Nat :=
  events.foldl (init := 0) fun acc e =>
    if acc == 0 then e.startNs else min acc e.startNs

def traceEndNs (events : Array Event) : Nat :=
  events.foldl (init := 0) fun acc e => max acc e.endNs

def reportTableRows (rows : Array SummaryRow) : String :=
  let rowHtml := rows.map fun r =>
    let pct := s!"{r.pct / 10}.{r.pct % 10}%"
    s!"<tr data-prof-row><td>{htmlEscape r.name}</td><td data-sort=\"{r.selfNs}\">{formatDuration r.selfNs}</td><td data-sort=\"{r.totalNs}\">{formatDuration r.totalNs}</td><td>{r.calls}</td><td>{pct}</td><td><div class=\"bar\"><span style=\"width:{min 100 (r.pct / 10)}%\"></span></div></td></tr>"
  String.intercalate "\n" rowHtml.toList

def phaseBarsHtml (events : Array Event) : String :=
  let totals := phaseTotals events
  let maxTotal := totals.foldl (init := 0) (fun acc r => max acc r.2)
  let rows := totals.map fun (phase, total) =>
    let w := if maxTotal == 0 then 0 else (total * 100) / maxTotal
    s!"<div class=\"phase\"><strong>{htmlEscape phase}</strong><span>{formatDuration total}</span><div class=\"bar\"><span style=\"width:{w}%\"></span></div></div>"
  String.intercalate "\n" rows.toList

def shapeRowsHtml (events : Array Event) : String :=
  let totals := shapeTotals events
  let rows := totals.extract 0 (min 20 totals.size)
  let rowHtml := rows.map fun (shape, total, calls) =>
    s!"<tr data-prof-row><td>{htmlEscape shape}</td><td data-sort=\"{total}\">{formatDuration total}</td><td>{calls}</td></tr>"
  String.intercalate "\n" rowHtml.toList

def moduleRowsHtml (events : Array Event) : String :=
  let rows := moduleTotals events
  let rowHtml := rows.map fun (name, total, calls, peak) =>
    s!"<tr data-prof-row data-module=\"{htmlEscape name}\"><td>{htmlEscape name}</td><td data-sort=\"{total}\">{formatDuration total}</td><td>{calls}</td><td data-sort=\"{peak}\">{peak}</td></tr>"
  if rowHtml.isEmpty then
    "<tr><td colspan=\"4\">No module context was recorded for this run.</td></tr>"
  else
    String.intercalate "\n" rowHtml.toList

def moduleBarsHtml (events : Array Event) : String :=
  let totals := moduleTotals events
  let maxTotal := totals.foldl (init := 0) (fun acc r => max acc r.2.1)
  let rows := totals.map fun (name, total, calls, peak) =>
    let w := if maxTotal == 0 then 0 else (total * 100) / maxTotal
    s!"<div class=\"phase\"><strong>{htmlEscape name}</strong><span>{formatDuration total}</span><div class=\"bar\"><span style=\"width:{w}%\"></span></div><small>{calls} events - peak {peak} bytes</small></div>"
  if rows.isEmpty then
    "<p class=\"lede\">No module context was recorded for this run.</p>"
  else
    String.intercalate "\n" rows.toList

def stepRowsHtml (events : Array Event) : String :=
  let rows := stepTotals events
  let rowHtml := rows.map fun (step, total, calls) =>
    s!"<tr data-prof-row data-phase=\"step\"><td>{step}</td><td data-sort=\"{total}\">{formatDuration total}</td><td>{calls}</td></tr>"
  if rowHtml.isEmpty then
    "<tr><td colspan=\"3\">No step context was recorded for this run.</td></tr>"
  else
    String.intercalate "\n" rowHtml.toList

def memoryRowsHtml (events : Array Event) : String :=
  let withMem := events.filter fun e => e.metadata.allocPeakBytes.isSome || e.metadata.allocLiveBytes.isSome
  let sorted := withMem.qsort fun a b =>
    a.metadata.allocPeakBytes.getD 0 > b.metadata.allocPeakBytes.getD 0
  let rows := sorted.extract 0 (min 30 sorted.size)
  let rowHtml := rows.map fun e =>
    let live := e.metadata.allocLiveBytes.getD 0
    let peak := e.metadata.allocPeakBytes.getD 0
    let delta :=
      match e.metadata.allocDeltaBytes with
      | some d => toString d
      | none => "-"
    let step :=
      match e.metadata.stepIndex with
      | some n => toString n
      | none => "-"
    s!"<tr {e.dataAttrs}><td>{e.index}</td><td>{htmlEscape e.name}</td><td>{htmlEscape step}</td><td data-sort=\"{peak}\">{peak}</td><td data-sort=\"{live}\">{live}</td><td>{htmlEscape delta}</td><td>{htmlEscape e.metadata.shapeLabel}</td></tr>"
  if rowHtml.isEmpty then
    "<tr><td colspan=\"7\">No allocator metadata was recorded for this run.</td></tr>"
  else
    String.intercalate "\n" rowHtml.toList

def timelineRowsHtml (events : Array Event) : String :=
  let start0 := traceStartNs events
  let end0 := traceEndNs events
  let span := max 1 (end0 - start0)
  let sorted := events.qsort (fun a b => a.durationNs > b.durationNs)
  let rows := (sorted.extract 0 (min 80 sorted.size)).qsort (fun a b => a.startNs < b.startNs)
  let rowHtml := rows.map fun e =>
    let left := ((e.startNs - start0) * 100) / span
    let width := max 1 ((e.durationNs * 100) / span)
    let color := phaseColor e.metadata.phaseName
    let step :=
      match e.metadata.stepIndex with
      | some n => s!"step {n}"
      | none => e.metadata.phaseName
    s!"<div class=\"tlrow\" {e.dataAttrs}><div class=\"tlmeta\"><strong>{htmlEscape e.name}</strong><span>{htmlEscape step} - {htmlEscape e.metadata.deviceName} - {formatDuration e.durationNs}</span></div><div class=\"tltrack\"><span style=\"left:{left}%;width:{min 100 width}%;background:{color}\"></span></div></div>"
  if rowHtml.isEmpty then
    "<p>No events were recorded.</p>"
  else
    String.intercalate "\n" rowHtml.toList

def memoryTimelineHtml (events : Array Event) : String :=
  let start0 := traceStartNs events
  let end0 := traceEndNs events
  let span := max 1 (end0 - start0)
  let withMem := events.filter fun e =>
    e.metadata.allocPeakBytes.isSome || e.metadata.allocLiveBytes.isSome || e.metadata.allocDeltaBytes.isSome
  let sorted := withMem.qsort fun a b =>
    allocDeltaMagnitude a > allocDeltaMagnitude b
  let rows := (sorted.extract 0 (min 80 sorted.size)).qsort (fun a b => a.startNs < b.startNs)
  let rowHtml := rows.map fun e =>
    let left := ((e.startNs - start0) * 100) / span
    let width := max 1 ((e.durationNs * 100) / span)
    let live := e.metadata.allocLiveBytes.getD 0
    let peak := e.metadata.allocPeakBytes.getD 0
    let delta :=
      match e.metadata.allocDeltaBytes with
      | some d => toString d
      | none => "-"
    let color := phaseColor e.metadata.phaseName
    s!"<div class=\"memrow\" {e.dataAttrs}><div class=\"tlmeta\"><strong>{htmlEscape e.name}</strong><span>live {live} - peak {peak} - delta {htmlEscape delta}</span></div><div class=\"tltrack\"><span style=\"left:{left}%;width:{min 100 width}%;background:{color}\"></span></div></div>"
  if rowHtml.isEmpty then
    "<p>No allocator metadata was recorded for this run.</p>"
  else
    String.intercalate "\n" rowHtml.toList

def slowEventRowsHtml (events : Array Event) : String :=
  let sorted := events.qsort (fun a b => a.durationNs > b.durationNs)
  let rows := sorted.extract 0 (min 40 sorted.size)
  let rowHtml := rows.map fun e =>
    let mem :=
      match e.metadata.allocLiveBytes, e.metadata.allocPeakBytes with
      | some live, some peak => s!"live={live} peak={peak}"
      | _, _ => "-"
    let step :=
      match e.metadata.stepIndex with
      | some n => toString n
      | none => "-"
    s!"<tr {e.dataAttrs}><td>{e.index}</td><td>{htmlEscape e.name}</td><td>{htmlEscape step}</td><td>{htmlEscape e.metadata.phaseName}</td><td>{htmlEscape e.metadata.deviceName}</td><td data-sort=\"{e.durationNs}\">{formatDuration e.durationNs}</td><td>{htmlEscape e.metadata.shapeLabel}</td><td>{htmlEscape mem}</td></tr>"
  String.intercalate "\n" rowHtml.toList

def phaseOpRowsHtml (events : Array Event) (phase : String) : String :=
  let rows := phaseOpRows events phase
  let limited := rows.extract 0 (min 40 rows.size)
  let rowHtml := limited.map fun r =>
    s!"<tr data-prof-row data-phase=\"{htmlEscape phase}\" data-op=\"{htmlEscape r.name}\"><td>{htmlEscape r.name}</td><td data-sort=\"{r.totalNs}\">{formatDuration r.totalNs}</td><td>{r.calls}</td><td data-sort=\"{r.peakBytes}\">{r.peakBytes}</td><td data-sort=\"{r.churnBytes}\">{r.churnBytes}</td></tr>"
  if rowHtml.isEmpty then
    s!"<tr><td colspan=\"5\">No {htmlEscape phase} events were recorded.</td></tr>"
  else
    String.intercalate "\n" rowHtml.toList

/--
Write the self-contained HTML report next to a trace path.

The report is deliberately boring to share: one file, no web server, no npm bundle. It gives a
quick review view (filters, forward/backward groups, memory timeline) while leaving full timeline
for Perfetto when someone needs to zoom in.
-/
def exportHtmlReport (tracePath : String) : IO Unit := do
  let events ← getEvents
  let summary := buildSummaryRows events
  let totalNs := events.foldl (init := 0) fun acc e => acc + e.durationNs
  let phaseOptions := filterOptionsHtml (uniqueMetadataValues events (fun m => m.phase))
  let moduleOptions := filterOptionsHtml (uniqueMetadataValues events (fun m => m.moduleName))
  let deviceOptions := filterOptionsHtml (uniqueMetadataValues events (fun m => m.device))
  let reportPath := reportPathForTrace tracePath
  let path : System.FilePath := reportPath
  if let some dir := path.parent then
    IO.FS.createDirAll dir
  let html := s!"<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>LeanProfiler Runtime Profile</title>
<style>
:root \{ --bg:#101314; --panel:#171c1f; --ink:#f4efe4; --muted:#9da7a9; --line:#2a3438; --hot:#f3a43b; --cool:#67c7d4; }
* \{ box-sizing:border-box; }
body \{ margin:0; background:radial-gradient(circle at 20% 0%, #203039, var(--bg) 42%); color:var(--ink); font:15px/1.55 ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif; }
main \{ width:min(1180px, calc(100% - 32px)); margin:36px auto 80px; }
h1 \{ font-size:clamp(32px, 5vw, 62px); line-height:.95; margin:0 0 14px; letter-spacing:-.05em; }
h2 \{ margin:38px 0 14px; font-size:24px; letter-spacing:-.03em; }
.lede \{ color:var(--muted); max-width:820px; font-size:18px; }
.cards \{ display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:14px; margin:24px 0; }
.card \{ background:rgba(23,28,31,.86); border:1px solid var(--line); border-radius:22px; padding:18px; box-shadow:0 18px 48px rgba(0,0,0,.25); }
.card .k \{ color:var(--muted); font-size:12px; text-transform:uppercase; letter-spacing:.12em; }
.card .v \{ font-size:24px; margin-top:6px; font-weight:750; }
.grid \{ display:grid; grid-template-columns:1fr 1fr; gap:18px; }
.panel \{ background:rgba(23,28,31,.88); border:1px solid var(--line); border-radius:24px; padding:18px; overflow:hidden; }
.phase \{ display:grid; grid-template-columns:140px 90px 1fr; gap:12px; align-items:center; margin:10px 0; }
.bar \{ height:12px; border-radius:99px; background:#273237; overflow:hidden; }
.bar span \{ display:block; height:100%; background:linear-gradient(90deg,var(--hot),var(--cool)); border-radius:inherit; }
table \{ width:100%; border-collapse:collapse; background:rgba(23,28,31,.88); border:1px solid var(--line); border-radius:20px; overflow:hidden; }
th,td \{ padding:10px 12px; border-bottom:1px solid var(--line); text-align:left; vertical-align:top; }
th \{ color:#ffd38b; font-size:12px; text-transform:uppercase; letter-spacing:.12em; cursor:pointer; user-select:none; }
td \{ color:#e6ded0; }
code,a \{ color:#8ee6f0; }
.toolbar \{ display:flex; gap:10px; align-items:center; margin:12px 0; }
input,select \{ width:320px; max-width:100%; background:#0c0f10; color:var(--ink); border:1px solid var(--line); border-radius:999px; padding:9px 13px; }
.controls \{ position:sticky; top:0; z-index:3; display:grid; grid-template-columns:2fr 1fr 1fr 1fr auto; gap:10px; align-items:center; margin:24px 0; padding:12px; background:rgba(16,19,20,.88); border:1px solid var(--line); border-radius:24px; backdrop-filter:blur(14px); }
.controls input,.controls select \{ width:100%; }
.controls button \{ background:#ffd38b; color:#14100c; border:0; border-radius:999px; padding:10px 14px; font-weight:750; cursor:pointer; }
.legend \{ display:flex; flex-wrap:wrap; gap:10px; color:var(--muted); font-size:13px; margin:8px 0 18px; }
.legend span \{ display:inline-flex; align-items:center; gap:6px; }
.legend i \{ display:inline-block; width:12px; height:12px; border-radius:999px; }
.timeline \{ display:grid; gap:8px; }
.tlrow,.memrow \{ display:grid; grid-template-columns:minmax(210px, 320px) 1fr; gap:12px; align-items:center; }
.tlmeta \{ color:var(--muted); font-size:12px; overflow:hidden; }
.tlmeta strong \{ display:block; color:var(--ink); white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.tlmeta span \{ white-space:nowrap; }
.tltrack \{ position:relative; height:15px; background:#263137; border-radius:999px; overflow:hidden; }
.tltrack span \{ position:absolute; top:0; bottom:0; min-width:2px; background:linear-gradient(90deg,var(--hot),var(--cool)); border-radius:999px; }
@media (max-width:800px) \{ .cards,.grid \{ grid-template-columns:1fr; } .phase \{ grid-template-columns:1fr; } }
@media (max-width:900px) \{ .controls \{ position:static; grid-template-columns:1fr; } }
</style>
</head>
<body>
<main>
<h1>LeanProfiler Runtime Profile</h1>
<p class=\"lede\">Generated from an opt-in LeanProfiler run. Downstream adapters may attach domain-specific fields such as CUDA synchronization, allocator state, tensor shapes, modules, or training steps.</p>
<div class=\"controls\">
  <input id=\"globalFilter\" placeholder=\"search modules, ops, shapes, phases\">
  <select id=\"phaseFilter\"><option value=\"\">all phases</option>{phaseOptions}</select>
  <select id=\"moduleFilter\"><option value=\"\">all modules</option>{moduleOptions}</select>
  <select id=\"deviceFilter\"><option value=\"\">all devices</option>{deviceOptions}</select>
  <button id=\"clearFilters\" type=\"button\">clear</button>
</div>
<div class=\"cards\">
<div class=\"card\"><div class=\"k\">Events</div><div class=\"v\">{events.size}</div></div>
<div class=\"card\"><div class=\"k\">Total Recorded</div><div class=\"v\">{formatDuration totalNs}</div></div>
<div class=\"card\"><div class=\"k\">Rows</div><div class=\"v\">{summary.size}</div></div>
<div class=\"card\"><div class=\"k\">Peak Bytes</div><div class=\"v\">{maxPeakBytes events}</div></div>
</div>
<div class=\"grid\">
<section class=\"panel\"><h2>Phase Split</h2>{phaseBarsHtml events}</section>
<section class=\"panel\"><h2>Modules</h2>{moduleBarsHtml events}</section>
<section class=\"panel\"><h2>Trace</h2><p>Open <code>{htmlEscape tracePath}</code> in <a href=\"https://ui.perfetto.dev\">Perfetto</a> for the full timeline.</p></section>
</div>
<section><h2>Top Groups</h2><div class=\"toolbar\"><input id=\"filterGroups\" placeholder=\"filter groups\"></div><table data-filter=\"filterGroups\"><thead><tr><th>Name</th><th>Self</th><th>Total</th><th>Calls</th><th>%</th><th>Bar</th></tr></thead><tbody>{reportTableRows summary}</tbody></table></section>
<section><h2>Module Table</h2><table><thead><tr><th>Module</th><th>Total</th><th>Events</th><th>Peak Bytes</th></tr></thead><tbody>{moduleRowsHtml events}</tbody></table></section>
<section><h2>Forward Operators</h2><table><thead><tr><th>Event</th><th>Total</th><th>Calls</th><th>Peak Bytes</th><th>Memory Churn</th></tr></thead><tbody>{phaseOpRowsHtml events "forward"}</tbody></table></section>
<section><h2>Backward Graph Nodes</h2><table><thead><tr><th>Graph Node</th><th>Total</th><th>Calls</th><th>Peak Bytes</th><th>Memory Churn</th></tr></thead><tbody>{phaseOpRowsHtml events "backward"}</tbody></table></section>
<section><h2>Optimizer / Step</h2><table><thead><tr><th>Span</th><th>Total</th><th>Calls</th><th>Peak Bytes</th><th>Memory Churn</th></tr></thead><tbody>{phaseOpRowsHtml events "step"}</tbody></table></section>
<section><h2>Steps</h2><table><thead><tr><th>Step</th><th>Total</th><th>Events</th></tr></thead><tbody>{stepRowsHtml events}</tbody></table></section>
<section class=\"panel\"><h2>Timeline Preview</h2><p class=\"lede\">The 80 slowest events, placed on the trace timeline. Use Perfetto for the full nested view.</p><div class=\"legend\"><span><i style=\"background:#f3a43b\"></i>forward</span><span><i style=\"background:#67c7d4\"></i>backward</span><span><i style=\"background:#9be26f\"></i>step</span></div><div class=\"timeline\">{timelineRowsHtml events}</div></section>
<section class=\"panel\"><h2>Memory Timeline</h2><p class=\"lede\">The allocator-heavy events, placed by time. This makes memory churn bursts easier to spot before opening the full trace.</p><div class=\"timeline\">{memoryTimelineHtml events}</div></section>
<section><h2>Top Memory</h2><div class=\"toolbar\"><input id=\"filterMemory\" placeholder=\"filter memory rows\"></div><table data-filter=\"filterMemory\"><thead><tr><th>#</th><th>Name</th><th>Step</th><th>Peak Bytes</th><th>Live Bytes</th><th>Delta</th><th>Shape</th></tr></thead><tbody>{memoryRowsHtml events}</tbody></table></section>
<section><h2>Top Shapes</h2><table><thead><tr><th>Shape</th><th>Total</th><th>Calls</th></tr></thead><tbody>{shapeRowsHtml events}</tbody></table></section>
<section><h2>Slowest Individual Events</h2><div class=\"toolbar\"><input id=\"filterEvents\" placeholder=\"filter events\"></div><table data-filter=\"filterEvents\"><thead><tr><th>#</th><th>Name</th><th>Step</th><th>Phase</th><th>Device</th><th>Duration</th><th>Shape</th><th>Memory</th></tr></thead><tbody>{slowEventRowsHtml events}</tbody></table></section>
</main>
<script>
function applyGlobalFilters() \{
  const q = (document.getElementById('globalFilter')?.value || '').toLowerCase();
  const phase = document.getElementById('phaseFilter')?.value || '';
  const moduleName = document.getElementById('moduleFilter')?.value || '';
  const device = document.getElementById('deviceFilter')?.value || '';
  for (const row of document.querySelectorAll('[data-prof-row]')) \{
    const text = row.innerText.toLowerCase();
    const rowPhase = row.dataset.phase || '';
    const rowModule = row.dataset.module || '';
    const rowDevice = row.dataset.device || '';
    const okText = !q || text.includes(q);
    const okPhase = !phase || rowPhase === phase || text.includes(phase.toLowerCase());
    const okModule = !moduleName || rowModule === moduleName || text.includes(moduleName.toLowerCase());
    const okDevice = !device || rowDevice === device || text.includes(device.toLowerCase());
    row.style.display = okText && okPhase && okModule && okDevice ? '' : 'none';
  }
}
for (const id of ['globalFilter','phaseFilter','moduleFilter','deviceFilter']) \{
  document.getElementById(id)?.addEventListener('input', applyGlobalFilters);
  document.getElementById(id)?.addEventListener('change', applyGlobalFilters);
}
document.getElementById('clearFilters')?.addEventListener('click', () => \{
  for (const id of ['globalFilter','phaseFilter','moduleFilter','deviceFilter']) \{
    const el = document.getElementById(id);
    if (el) el.value = '';
  }
  applyGlobalFilters();
});
for (const table of document.querySelectorAll('table')) \{
  for (const th of table.querySelectorAll('th')) \{
    th.addEventListener('click', () => \{
      const idx = Array.from(th.parentNode.children).indexOf(th);
      const rows = Array.from(table.tBodies[0].rows);
      const numeric = rows.every(r => r.cells[idx]?.dataset.sort);
      rows.sort((a,b) => \{
        const av = numeric ? Number(a.cells[idx].dataset.sort) : a.cells[idx].innerText;
        const bv = numeric ? Number(b.cells[idx].dataset.sort) : b.cells[idx].innerText;
        return numeric ? bv - av : String(av).localeCompare(String(bv));
      });
      rows.forEach(r => table.tBodies[0].appendChild(r));
    });
  }
  const filterId = table.dataset.filter;
  if (filterId) \{
    const input = document.getElementById(filterId);
    input?.addEventListener('input', () => \{
      const q = input.value.toLowerCase();
      for (const row of table.tBodies[0].rows) row.style.display = row.innerText.toLowerCase().includes(q) ? '' : 'none';
    });
  }
}
</script>
</body>
</html>"
  IO.FS.writeFile path html

/-! ## Finalization Helpers -/

inductive RuntimeOutput where
  | summary
  | trace
  | html
  | all
  deriving Repr, BEq

/-- Write selected profiler artifacts at most once. -/
def finish (output : RuntimeOutput) (tracePath : String) : IO Unit := do
  let shouldFinish ← profilerState.atomically do
    let state ← get
    if state.ended then
      pure false
    else
      set { state with ended := true }
      pure true
  if shouldFinish then
    match output with
    | .summary =>
        printSummary
    | .trace =>
        exportTrace tracePath
        IO.println s!"Lean profile trace: {tracePath} -> https://ui.perfetto.dev"
    | .html =>
        exportHtmlReport tracePath
        IO.println s!"Lean profile report: {reportPathForTrace tracePath}"
    | .all =>
        exportTrace tracePath
        exportHtmlReport tracePath
        printSummary
        IO.println s!"Lean profile trace: {tracePath} -> https://ui.perfetto.dev"
        IO.println s!"Lean profile report: {reportPathForTrace tracePath}"

/-- Profile an arbitrary `IO` block and print only the terminal summary. -/
def profileIOSummary {α : Type} (name : String) (action : IO α) : IO α := do
  clear
  try
    recordSpanWith name { phase := some "manual" } action
  finally
    finish .summary "build/leanprofiler-trace.json"


end LeanProfiler
