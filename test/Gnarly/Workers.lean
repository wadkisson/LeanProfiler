import LeanProfiler
import test.Gnarly.Core
import test.Gnarly.Compiler
import test.Gnarly.Cache
import test.Gnarly.Graph

structure Job where
  id : Nat
  payload : String
  deriving Repr

def makeJobs (n : Nat) : List Job :=
  (List.range n).map fun i =>
    { id := i, payload := s!"job-{i}-payload" }

@[profile]
def runJob (j : Job) : IO Nat := do
  pulse s!"worker.job.{j.id}" 1
  let compiled ← compileSource j.payload
  let cached ← cacheGetOrCompute j.id
  pure (compiled.length + cached)

@[profile]
def drainQueue (jobs : List Job) : IO Nat := do
  let mut acc := 0
  for j in jobs do
    let n ← runJob j
    acc := acc + n
  pure acc

def splitJobs (workers : Nat) (jobs : List Job) : List (List Job) :=
  if workers == 0 then
    []
  else
    (List.range workers).map fun w =>
      jobs.zipIdx.filter (fun (_, i) => i % workers == w) |>.map Prod.fst

@[profile]
def workerPool (workers : Nat) (jobs : List Job) : IO Nat := do
  let chunks := splitJobs (max workers 1) jobs
  let mut total := 0
  for w in List.range chunks.length do
    let chunk := chunks[w]!
    let n ← drainQueue chunk
    total := total + n
  pure total

@[profile]
def schedulerBurst (rounds : Nat) : IO Nat := do
  let mut grand := 0
  for r in List.range rounds do
    let jobs := makeJobs (3 + r)
    let n ← workerPool (2 + r % 2) jobs
    grand := grand + n
  pure grand
