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

/-- Wrap a block in a named span. Use inside `IO` `do` for manual sub-regions. -/
def profile [Monad m] [MonadFinally m]
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

/-- `@[profile]` expands to this (same as `profile`). -/
def withProfile [Monad m] [MonadFinally m]
    [MonadLiftT (ST IO.RealWorld) m] [MonadLiftT BaseIO m]
    (name : String) (action : m α) : m α :=
  profile name action

/-- Setup then side effects, return the setup value (avoids trailing `pure x`). -/
def profileLet [Monad m] [MonadFinally m]
    [MonadLiftT (ST IO.RealWorld) m] [MonadLiftT BaseIO m]
    (name : String) (setup : m α) (body : α → m Unit) : m α := do
  profile name do
    let x ← setup
    body x
    return x

def getEvents : IO (Array ProfileEvent) :=
  eventLog.get
