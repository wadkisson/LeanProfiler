import LeanProfiler
import test.Gnarly.Core

structure Node where
  id : Nat
  weight : Nat
  neighbors : List Nat
  deriving Repr

def sampleGraph : List Node := [
  { id := 0, weight := 2, neighbors := [1, 2, 3] },
  { id := 1, weight := 1, neighbors := [4, 5] },
  { id := 2, weight := 3, neighbors := [5, 6] },
  { id := 3, weight := 1, neighbors := [6] },
  { id := 4, weight := 2, neighbors := [7] },
  { id := 5, weight := 1, neighbors := [7, 8] },
  { id := 6, weight := 2, neighbors := [8] },
  { id := 7, weight := 1, neighbors := [] },
  { id := 8, weight := 1, neighbors := [] }
]

def findNode (id : Nat) (g : List Node) : Option Node :=
  g.find? (·.id == id)

@[profile]
def visitNode (n : Node) : IO Nat := do
  pulse s!"graph.node.{n.id}" n.weight
  pure (n.id + n.weight)

partial def dfs (g : List Node) (cur : Nat) (budget : Nat) (seen : List Nat) : IO Nat := do
  if budget == 0 then
    return 0
  match findNode cur g with
  | none => return 0
  | some node =>
    let score ← visitNode node
    let mut total := score
    for next in node.neighbors do
      unless seen.contains next do
        let sub ← dfs g next (budget - 1) (next :: seen)
        total := total + sub
    return total

@[profile]
def walkGraph (start : Nat) (depth : Nat) : IO Nat := do
  dfs sampleGraph start depth []

def bfsLayer (g : List Node) (frontier : List Nat) : IO (List Nat × Nat) := do
  let mut next : List Nat := []
  let mut score := 0
  for id in frontier do
    match findNode id g with
    | none => pure ()
    | some node =>
      let s ← visitNode node
      score := score + s
      for n in node.neighbors do
        unless next.contains n || frontier.contains n do
          next := next ++ [n]
  return (next, score)

@[profile]
def walkBreadth (start : Nat) (layers : Nat) : IO Nat := do
  let mut frontier := [start]
  let mut total := 0
  for _ in List.range layers do
    let (nxt, s) ← bfsLayer sampleGraph frontier
    total := total + s
    frontier := nxt
  pure total

@[profile]
def graphWhileJobs (iter : Nat) : IO Nat := do
  let mut acc := 0
  let mut i := 0
  while i < iter do
    let d ← walkBreadth (i % 9) 3
    let b ← walkGraph i 3
    acc := acc + d + b
    i := i + 1
  pure acc
