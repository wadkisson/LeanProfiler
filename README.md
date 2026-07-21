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

```lean
import LeanProfiler
open LeanProfiler

profiled def loadBatch (n : Nat) : IO (Array Nat) :=
  pure (Array.range n)

profiled def main : IO Unit := do
  let data ← span "load" (loadBatch 1024)
  let sum ← span "reduce" (data.foldl (· + ·) 0)
  IO.println s!"sum = {sum}"
```

```bash
LEAN_PROFILE=1 lake exe myapp   # summary + build/leanprofiler-trace.json
lake exe myapp                  # off
```

`LEAN_PROFILE` is off when unset/`""`/`"0"`/`"false"`. `LEAN_PROFILE_OUT` sets the trace path
(default `build/leanprofiler-trace.json`). Open the JSON in [Perfetto](https://ui.perfetto.dev).

Pure expressions inside `span` are forced with `IO.lazyPure` so the optimizer cannot float work out
of the timed region.

## Demo

```bash
LEAN_PROFILE=1 lake exe leanprofiler
```

## What it isn't

Not a Lean elaboration profiler (`set_option profiler`), and not a CUDA/hardware profiler — host-side
spans only.

## License

MIT
