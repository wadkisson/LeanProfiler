module

public import LeanProfiler.Option
public import Lean

@[expose] public section

def padRight (s : String) (width : Nat) : String :=
  if s.length >= width then s
  else s ++ String.ofList (List.replicate (width - s.length) ' ')

def padLeft (s : String) (width : Nat) : String :=
  if s.length >= width then s
  else String.ofList (List.replicate (width - s.length) ' ') ++ s

/-- Summary column width; long qualified names show the distinguishing suffix. -/
def summaryNameWidth : Nat := 56

def displayName (name : String) (width : Nat := summaryNameWidth) : String :=
  if name.length ≤ width then
    name
  else
    let keep := width - 3
    "..." ++ (name.drop (name.length - keep))

structure ProfileEvent where
  name : String
  startNs : Nat
  endNs : Nat
  depth : Nat
  deriving Repr

initialize eventLog : IO.Ref (Array ProfileEvent) ← IO.mkRef #[]
initialize currentDepth : IO.Ref Nat ← IO.mkRef 0
/-- When > 0, auto-wrapped defs record timings (started by `runProfiledMain` / `withProfile`). -/
initialize profilingScopeDepth : IO.Ref Nat ← IO.mkRef 0

def bracketEvent [Monad m] [MonadFinally m]
    [MonadLiftT (ST IO.RealWorld) m] [MonadLiftT BaseIO m]
    (name : String) (action : m α) : m α := do
  let start ← IO.monoNanosNow
  let depth ← currentDepth.get
  currentDepth.set (depth + 1)
  try
    action
  finally
    currentDepth.set depth
    let stop ← IO.monoNanosNow
    eventLog.modify (·.push { name, startNs := start, endNs := stop, depth })

/-- Manual region: starts the profiling scope and records this label. -/
def withProfile [Monad m] [MonadFinally m]
    [MonadLiftT (ST IO.RealWorld) m] [MonadLiftT BaseIO m]
    (name : String) (action : m α) : m α := do
  profilingScopeDepth.modify (· + 1)
  try
    bracketEvent name action
  finally
    profilingScopeDepth.modify (· - 1)

/-- Used by auto-instrumentation: record only while a scope is active (~one ref read otherwise). -/
def withProfileWhenActive [Monad m] [MonadFinally m]
    [MonadLiftT (ST IO.RealWorld) m] [MonadLiftT BaseIO m]
    (name : String) (action : m α) : m α := do
  if (← profilingScopeDepth.get) == 0 then
    action
  else
    bracketEvent name action

/-- Open the profiling scope once at program entry (`IO UInt32` Lake exes supported). -/
def profileRun (action : IO α) : IO α :=
  withProfile "run" action

/-- Named entry scope when you run several commands from one executable. -/
def profileRunNamed (name : String) (action : IO α) : IO α :=
  withProfile name action

/-- Alias for older call sites. Prefer `profileRun`. -/
def runProfiledMain (action : IO α) : IO α :=
  profileRun action

/-- Pure defs: times body only while profiling scope is active. -/
unsafe def profilePure [Inhabited α] (name : String) (body : α) : α :=
  unsafeBaseIO do
    if (← profilingScopeDepth.get) == 0 then
      return body
    profilingScopeDepth.modify (· + 1)
    try
      let start ← IO.monoNanosNow
      let depth ← currentDepth.get
      currentDepth.set (depth + 1)
      let r := body
      currentDepth.set depth
      let stop ← IO.monoNanosNow
      eventLog.modify (·.push { name, startNs := start, endNs := stop, depth })
      return r
    finally
      profilingScopeDepth.modify (· - 1)

def exportProfile (path : System.FilePath) : IO Unit := do
  let events ← eventLog.get
  let q := "\""
  let eventStrs := events.map fun e =>
    let dur := e.endNs - e.startNs
    s!"\{{q}name{q}:{q}{e.name}{q},{q}cat{q}:{q}lean{q},{q}ph{q}:{q}X{q},{q}ts{q}:{e.startNs},{q}dur{q}:{dur},{q}pid{q}:1,{q}tid{q}:1}"
  let joined := String.intercalate ",\n  " eventStrs.toList
  let json := s!"\{{q}displayTimeUnit{q}:{q}ns{q},{q}traceEvents{q}:[\n  {joined}\n]}"
  IO.FS.writeFile path json

def formatDuration (ns : Nat) : String :=
  if ns < 1000 then s!"{ns} ns"
  else if ns < 1_000_000 then
    let scaled := (ns * 100) / 1000
    s!"{scaled / 100}.{(scaled % 100) / 10}{scaled % 10} us"
  else if ns < 1_000_000_000 then
    let scaled := (ns * 100) / 1_000_000
    s!"{scaled / 100}.{(scaled % 100) / 10}{scaled % 10} ms"
  else
    let scaled := (ns * 100) / 1_000_000_000
    s!"{scaled / 100}.{(scaled % 100) / 10}{scaled % 10} s"

def printSummary : IO Unit := do
  let events ← eventLog.get
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
  let w := summaryNameWidth
  let rule := String.ofList (List.replicate w '-')
  IO.println ""
  IO.println s!"{padRight "Name" w} {padLeft "Self Time" 12} {padLeft "Total Time" 12} {padLeft "Calls" 8} {padLeft "% Total" 8}"
  IO.println s!"{rule} ------------ ------------ -------- --------"
  for (name, total, self, calls) in sorted do
    let pct := if totalSelf == 0 then 0 else (self * 1000) / totalSelf
    let pctStr := s!"{pct / 10}.{pct % 10}%"
    IO.println s!"{padRight (displayName name w) w} {padLeft (formatDuration self) 12} {padLeft (formatDuration total) 12} {padLeft (toString calls) 8} {padLeft pctStr 8}"
