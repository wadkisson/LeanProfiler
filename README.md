# LeanProfiler

Time **only the functions you mark**, with **one** entry wrapper.

## Recipe (3 steps)

**1. Lake**

```toml
[[require]]
name = "LeanProfiler"
git = "https://github.com/wadkisson/LeanProfiler"
rev = "main"
```

**2. Tag hot `def`s** (same file as the implementation):

```lean
import LeanProfiler

@[profile]
def forward (input : List Float) : IO (List Float) := do
  ...
```

**3. Open scope at entry and print**

```lean
def main : IO UInt32 := profileRun do
  train
  printSummary
  pure 0
```

Optional: `exportProfile "trace.json"` then open at [ui.perfetto.dev](https://ui.perfetto.dev).

## How it works

| Piece | Role |
|-------|------|
| `profileRun` | One call at `main` (or your CLI entry). Sets `profilingScopeDepth > 0` for the whole run. |
| `@[profile]` | Compile-time wrap on **that def only** → `withProfileWhenActive "Full.Name" …` |
| `withProfile "label"` | Manual region inside a big `do` (training loop, etc.) |
| `printSummary` | Aggregated self/total time table |

While the scope is **off**, `@[profile]` defs are a single ref check per call. Inside `profileRun`, they record timings.

**Not wrapped:** `Except` / `Result` parsers, `partial` defs, anything without `@[profile]` (unless you enable legacy `set_option profiler.instrument true` on the whole file).

## Pure tensor code

```lean
set_option profiler.pure true

@[profile]
def matmul ... := ...
```

## Legacy file-wide mode

```lean
set_option profiler.instrument true  -- every IO def in this file
```

Prefer `@[profile]` on 5–15 hot defs instead of instrumenting hundreds of ops.

## Limits

- Simple `def := term` shapes only.
- ~tens of µs per recorded call — profile layers, not every tiny helper.
