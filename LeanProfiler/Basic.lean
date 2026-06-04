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

/-- Record time for a named region. Use in `do` blocks around code you want timed. -/
def withProfile [Monad m] [MonadFinally m]
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
