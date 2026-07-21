# LeanProfiler

A tiny runtime profiler for compiled Lean programs. Wrap the regions you care about, and LeanProfiler prints a terminal summary plus a Chrome/Perfetto JSON trace.

Toggled by `LEAN_PROFILE`. When off, instrumented calls cost a single boolean check.

## Install

Add to your `lakefile.toml`, then `lake update`:

```toml
[[require]]
name = "LeanProfiler"
git = "https://github.com/wadkisson/LeanProfiler"
rev = "main"
```

Use the same toolchain as this repo.

## Usage

Two names:

| Name | Use |
|------|-----|
| `profiled def f := ...` | Profile a whole function. On `main`, also clears on entry and writes output on exit. |
| `span "name" (expr)` | Profile a sub-region — any expression, pure or `IO`. |

### Example:

```lean
def loadBatch (n : Nat) : IO (Array Nat) :=
  pure (Array.range n)

def main : IO Unit := do
  let data ← loadBatch 1024
  IO.println s!"loaded {data.size}"
```

### Option 1 — `profiled def` (time the whole function)

```lean
import LeanProfiler
open LeanProfiler

profiled def loadBatch (n : Nat) : IO (Array Nat) :=
  pure (Array.range n)

profiled def main : IO Unit := do
  let data ← loadBatch 1024
  IO.println s!"loaded {data.size}"
```

Every call to `loadBatch` becomes one summary row named `loadBatch`. `profiled def main` clears on entry and writes the report on exit.

### Option 2 — `span` (time a piece inside)

```lean
import LeanProfiler
open LeanProfiler

def loadBatch (n : Nat) : IO (Array Nat) :=
  pure (Array.range n)

profiled def main : IO Unit := do
  let data ← span "load" (loadBatch 1024)
  IO.println s!"loaded {data.size}"
```

`loadBatch` stays a normal `def`. Only the wrapped expression is timed, under the name you chose (`load`). Still use `profiled def main` so the report is written.

```bash
LEAN_PROFILE=1 lake exe myapp   # summary + build/leanprofiler-trace.json
lake exe myapp                  # off
```

`LEAN_PROFILE` is off when unset/`""`/`"0"`/`"false"`. `LEAN_PROFILE_OUT` sets the trace path
(default `build/leanprofiler-trace.json`). Open the JSON in [Perfetto](https://ui.perfetto.dev).

Pure expressions inside `span` are forced with `IO.lazyPure` so the optimizer cannot float work out
of the timed region.

## License

MIT
