import LeanProfiler

open LeanProfiler

partial def findRow (name : String) (rows : Array SummaryRow) : Option SummaryRow := Id.run do
  for row in rows do
    if row.name == name then
      return some row
  return none

def summaryCheck : IO Unit := do
  let outer : Event := { name := "outer", startNs := 0, endNs := 10, depth := 0, index := 0 }
  let inner : Event :=
    { name := "inner", startNs := 2, endNs := 5, depth := 1, index := 1, parentIndex := some 0 }
  let rows := buildSummaryRows #[outer, inner]
  match findRow "outer" rows, findRow "inner" rows with
  | some outerRow, some innerRow =>
      if outerRow.totalNs != 10 || outerRow.selfNs != 7 ||
          innerRow.totalNs != 3 || innerRow.selfNs != 3 then
        throw <| IO.userError "bad self-time summary rows"
  | _, _ => throw <| IO.userError "missing summary rows"

def hookCheck : IO Unit := do
  clear
  let hooks : SpanHooks :=
    { before := pure ()
      after := fun metadata => pure { metadata with timing := some "device-synchronized" } }
  recordSpanWithHooks "hooked" { phase := some "forward" } hooks do
    pure ()
  let events ← getEvents
  match events[0]? with
  | some event =>
      if event.metadata.timing != some "device-synchronized" then
        throw <| IO.userError "hook metadata was not attached"
  | none => throw <| IO.userError "hook did not record an event"

def hookFailureCheck : IO Unit := do
  clear
  let hooks : SpanHooks :=
    { before := pure ()
      after := fun _ => throw <| IO.userError "hook failed" }
  recordSpanWithHooks "hook-failure" { phase := some "forward" } hooks do
    pure ()
  let events ← getEvents
  match events[0]? with
  | some event =>
      if event.name != "hook-failure" || event.metadata.phase != some "forward" then
        throw <| IO.userError "span was not recorded after hook failure"
  | none => throw <| IO.userError "hook failure lost the span"

def contextFailureCheck : IO Unit := do
  clear
  try
    withModule "bad.module" do
      recordSpan "boom" do
        throw <| IO.userError "expected failure"
  catch _ =>
    pure ()
  recordSpan "after" do
    pure ()
  let events ← getEvents
  match events[1]? with
  | some event =>
      if event.metadata.moduleName.isSome then
        throw <| IO.userError "context leaked after failure"
  | none => throw <| IO.userError "missing post-failure event"

def runTask (task : Task (Except IO.Error Unit)) : IO Unit := do
  match task.get with
  | Except.ok () => pure ()
  | Except.error error => throw error

def concurrentAppendCheck : IO Unit := do
  clear
  let taskCount := 8
  let spansPerTask := 32
  let mut tasks : Array (Task (Except IO.Error Unit)) := #[]
  for taskIndex in [0:taskCount] do
    let task ← IO.asTask (prio := Task.Priority.dedicated) do
      for spanIndex in [0:spansPerTask] do
        recordSpanWith "concurrent"
          { phase := some "test", stepIndex := some taskIndex, graphNode := some s!"span_{spanIndex}" } do
          pure ()
    tasks := tasks.push task
  for task in tasks do
    runTask task
  let events ← getEvents
  if events.size != taskCount * spansPerTask then
    throw <| IO.userError "concurrent spans were dropped"
  let mut seen : Std.HashMap Nat Unit := {}
  for event in events do
    if seen.contains event.index then
      throw <| IO.userError "duplicate event index"
    if event.depth != 0 || event.parentIndex.isSome then
      throw <| IO.userError "independent concurrent spans should not inherit global nesting"
    seen := seen.insert event.index ()

def crossTaskParentCheck : IO Unit := do
  clear
  recordSpan "parent" do
    let parent? ← currentSpanIndex
    match parent? with
    | none => throw <| IO.userError "missing current parent span"
    | some parent =>
        let task ← IO.asTask (prio := Task.Priority.dedicated) do
          withParentIndex parent do
            recordSpan "child" do
              pure ()
        runTask task
  let events ← getEvents
  let parent? := events.find? (fun event => event.name == "parent")
  let child? := events.find? (fun event => event.name == "child")
  match parent?, child? with
  | some parent, some child =>
      if child.parentIndex != some parent.index || child.depth != parent.depth + 1 then
        throw <| IO.userError "cross-task parent link was not preserved"
  | _, _ => throw <| IO.userError "missing cross-task parent/child event"

def main : IO Unit := do
  summaryCheck
  hookCheck
  hookFailureCheck
  contextFailureCheck
  concurrentAppendCheck
  crossTaskParentCheck
  IO.println "runtime checks passed"
