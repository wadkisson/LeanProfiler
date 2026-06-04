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
  boot
  let d ← walkGraph 0 4
  let b ← walkBreadth 0 4
  IO.println s!"graph dfs={d} bfs={b}"
  let n ← compileBatch fakeSources
  IO.println s!"compiled {n} objects"
  let c ← cacheStress 4
  IO.println s!"cache stress score = {c}"
  let w ← schedulerBurst 3
  IO.println s!"worker scheduler total = {w}"
  let g ← graphWhileJobs 5
  IO.println s!"graph+while total = {g}"
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
