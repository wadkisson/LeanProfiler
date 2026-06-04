import LeanProfiler
import test.Gnarly.Core
import test.Gnarly.Graph

set_option profiler.rewrite true

mutual
partial def ping (n : Nat) : IO Nat := do
  if n == 0 then
    pulse "recurse.ping.base" 1
    pure 0
  else
    let q ← pong (n - 1)
    pure (n + q)

partial def pong (n : Nat) : IO Nat := do
  if n == 0 then
    pulse "recurse.pong.base" 1
    pure 1
  else
    let p ← ping (n - 1)
    pure (p * 2)
end

@[profile]
def mutualRecursion (depth : Nat) : IO Nat := do
  withProfile "recurse.entry" do
    ping depth

partial def knot (a b : Nat) : IO Nat := do
  if a == 0 then
    pure b
  else if b == 0 then
    pure a
  else
    let x ← knot (a - 1) b
    let y ← knot a (b - 1)
    pulse s!"recurse.knot.{a}.{b}" 1
    pure (x + y + 1)

def knotProfiled (a b : Nat) : IO Nat :=
  withProfile s!"recurse.knot.{a}.{b}" do
    knot a b

def spinLockCheck (rounds : Nat) : IO Nat := do
  let mut acc := 0
  for r in List.range rounds do
    let v ← withProfile s!"recurse.spin.{r}" do
      mutualRecursion (3 + r % 4)
    acc := acc + v
  pure acc

def knotGrid (n m : Nat) : IO Nat := do
  let mut total := 0
  for i in List.range n do
    for j in List.range m do
      let v ← withProfile s!"recurse.grid.{i}.{j}" do
        knotProfiled (1 + i % 3) (1 + j % 3)
      total := total + v
  pure total
