# LeanProfiler

Import the library, mark IO functions with `@[profile]`, call `printSummary` when done.

```lean
import LeanProfiler

@[profile]
def hotStep : IO Unit := do ...

def main : IO Unit := do
  hotStep
  printSummary
```

Each profiled file needs `import LeanProfiler` (the rewriter runs per file).

IO `def`s only. Skips `partial` defs and `Except` / `Result` returns automatically.

Optional: `exportFlameGraph "trace.json"` then open at [ui.perfetto.dev](https://ui.perfetto.dev).
