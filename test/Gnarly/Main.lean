import LeanProfiler
import test.Gnarly.Core
import test.Gnarly.Graph
import test.Gnarly.Compiler
import test.Gnarly.Cache
import test.Gnarly.Workers
import test.Gnarly.Recursion

set_option profiler.rewrite true

@[profile]
def boot : IO Unit := do
  emit "gnarly" "boot sequence"
  forEachIdx 4 fun i => pulse s!"boot.{i}" 1

def main : IO Unit := do
  IO.println "╔══════════════════════════════════════════╗"
  IO.println "║   LeanProfiler Gnarly — stress harness     ║"
  IO.println "╚══════════════════════════════════════════╝"
  IO.println ""

  withProfile "gnarly.total" do
    withProfile "gnarly.boot" do
      boot

    withProfile "gnarly.graph" do
      let d ← walkGraph 0 4
      let b ← walkBreadth 0 4
      IO.println s!"graph dfs={d} bfs={b}"

    withProfile "gnarly.compiler" do
      let n ← compileBatch fakeSources
      IO.println s!"compiled {n} objects"

    withProfile "gnarly.cache" do
      let c ← cacheStress 4
      IO.println s!"cache stress score = {c}"

    withProfile "gnarly.workers" do
      let w ← schedulerBurst 3
      IO.println s!"worker scheduler total = {w}"

    withProfile "gnarly.graphWhile" do
      let g ← graphWhileJobs 5
      IO.println s!"graph+while total = {g}"

    withProfile "gnarly.recursion" do
      let r ← spinLockCheck 3
      let k ← knotGrid 3 3
      IO.println s!"recursion r={r} knot={k}"

  IO.println ""
  IO.println "── summary (top by self time) ──"
  printSummary
  exportFlameGraph "build/gnarly-trace.json"
  IO.println ""
  IO.println "Flame graph: build/gnarly-trace.json → https://ui.perfetto.dev"
