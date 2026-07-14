structure Meta where
  phase : Option String := none

def recordSpanWith {α : Type} (_name : String) (_m : Meta) (action : IO α) : IO α := action

class Spannable (γ : Type) (α : outParam Type) where
  toIO : γ → IO α

instance (priority := 100) {α : Type} : Spannable (IO α) α := ⟨id⟩
instance {α : Type} : Spannable (Unit → α) α := ⟨IO.lazyPure⟩

@[inline] def span {γ α : Type} [Spannable γ α]
    (name : String) (body : γ) (metadata : Meta := {}) : IO α :=
  let action := Spannable.toIO body
  recordSpanWith name metadata action

def matmul (x : Nat) : Nat := x + 1

-- pure body (thunk)
def a : IO Nat := span "matmul" (fun _ => matmul 3)
-- pure body with metadata
def b : IO Nat := span "matmul" (fun _ => matmul 3) { phase := some "forward" }
-- IO body
def c : IO Unit := span "load" (IO.println "hi")
-- IO body with metadata
def d : IO Unit := span "load" (IO.println "hi") { phase := some "setup" }
-- IO body as do-block
def e : IO Nat := span "blk" do
  IO.println "x"
  pure 7

#eval a
#eval b
#eval e
