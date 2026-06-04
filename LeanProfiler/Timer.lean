module

public import Lean

@[expose] public section

structure ProfileEvent where
  name : String
  startNs : Nat
  endNs : Nat
  depth : Nat
  deriving Repr

initialize eventLog : IO.Ref (Array ProfileEvent) ← IO.mkRef #[]
initialize currentDepth : IO.Ref Nat ← IO.mkRef 0

/-- Time a named region. Wrap code manually, or use `set_option profiler.rewrite true` + `@[profile]`. -/
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

def getEvents : IO (Array ProfileEvent) :=
  eventLog.get

def clearEvents : IO Unit :=
  eventLog.set #[]
