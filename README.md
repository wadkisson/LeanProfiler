# LeanProfiler

Three modules:

| File | Role |
|------|------|
| `LeanProfiler/Timer.lean` | `withProfile` — the timer |
| `LeanProfiler/Rewrite.lean` | `set_option profiler.rewrite true` + `@[profile]` — rewrite IO defs at elaboration |
| `LeanProfiler/Summary.lean` | `printSummary`, `exportFlameGraph` — table + Perfetto flame timeline |

```lean
import LeanProfiler

set_option profiler.rewrite true

@[profile]
def hot : IO Unit := do ...

def main : IO Unit := do
  withProfile "main" do
    hot
  printSummary
  exportFlameGraph "trace.json"  -- ui.perfetto.dev
```
