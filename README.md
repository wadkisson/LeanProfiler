# LeanProfiler

Time regions with `withProfile`, optionally auto-wrap `@[profile]` IO defs, then `printSummary`.

## Manual profiling

```lean
import LeanProfiler

def main : IO Unit := do
  withProfile "load" do
    ...
  withProfile "train" do
    ...
  printSummary
```

## Optional auto-rewrite

```lean
set_option profiler.rewrite true

@[profile]
def trainStep : IO Unit := do
  ...
```

With `profiler.rewrite` on, the macro wraps that def’s body in `withProfile "Full.Name" …`. Without it, `@[profile]` is only a label (no rewrite).

## Limits

- IO `def`s only (`Except` / `Result` / `partial` are skipped).
- Simple `def := …` shapes only.
