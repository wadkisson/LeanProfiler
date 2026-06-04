import LeanProfiler
import test.Gnarly.Core
import test.Gnarly.Graph
import test.Gnarly.Compiler
import test.Gnarly.Cache
import test.Gnarly.Workers
import test.Gnarly.Recursion

@[profile]
def boot : IO Unit := do
  emit "gnarly" "boot sequence"
  forEachIdx 4 fun i => pulse s!"boot.{i}" 1

@[profile]
def runGnarly : IO Unit := do
  profile "boot" do
    boot

  profile "graph" do
    let d ← walkGraph 0 4
    let b ← walkBreadth 0 4
    IO.println s!"graph dfs={d} bfs={b}"

  profile "compile" do
    let n ← compileBatch fakeSources
    IO.println s!"compiled {n} objects"

  profile "cache" do
    let c ← cacheStress 4
    IO.println s!"cache stress score = {c}"

  profile "workers" do
    let w ← schedulerBurst 3
    IO.println s!"worker scheduler total = {w}"

  profile "graphWhile" do
    let g ← graphWhileJobs 5
    IO.println s!"graph+while total = {g}"

  profile "recursion" do
    let r ← spinLockCheck 3
    let k ← knotGrid 3 3
    IO.println s!"recursion r={r} knot={k}"

def main : IO Unit := do
  IO.println "╔══════════════════════════════════════════╗"
  IO.println "║   LeanProfiler Gnarly — stress harness     ║"
  IO.println "╚══════════════════════════════════════════╝"
  IO.println ""
  runGnarly
  IO.println ""
  IO.println "── summary ──"
  printSummary
  exportFlameGraph "build/gnarly-trace.json"
