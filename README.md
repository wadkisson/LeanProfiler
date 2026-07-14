# LeanProfiler

A small runtime profiler for compiled Lean programs. Wrap the regions you care about; it times them
and emits a terminal summary, a Chrome/Perfetto trace, and a self-contained HTML report.

Everything is toggled by the `LEAN_PROFILE` environment variable. When it's off, instrumented calls
cost a single boolean check.

Want to see it on a real model? [`Example/`](Example/README.md) profiles a small transformer and uses
the report to find (and fix) a bottleneck that isn't where you'd expect.

## Install

Add it to your `lakefile.toml`, then run `lake update`:

```toml
[[require]]
name = "LeanProfiler"
git = "https://github.com/wadkisson/LeanProfiler"
rev = "main"
```

Use the same toolchain as LeanProfiler (`leanprover/lean4:v4.30.0`, see `lean-toolchain`).

## Quick start

```lean
import LeanProfiler
open LeanProfiler

profiled def loadBatch (n : Nat) : IO (Array Nat) :=
  pure (Array.range n)

profiled_main def main : IO Unit := do
  let _ ← loadBatch 1024
  pure ()
```

```bash
LEAN_PROFILE=1 lake exe myapp    # records, then writes summary + trace + HTML at exit
lake exe myapp                   # off: instrumented calls are ~no-ops
```

`LEAN_PROFILE` is off when unset/`""`/`"0"`/`"false"`, on otherwise. `LEAN_PROFILE_OUT` sets the
trace path (default `build/leanprofiler-trace.json`); the HTML report is that path + `.html`.

## The five names

| Name | Use |
|------|-----|
| `profiled def f := ...` | profile a whole `IO` function (span named after it) |
| `profiled_main def main := ...` | wrap the entry point: `clear` on entry, `finish .all` on exit |
| `span "name" do ...` | profile an `IO` block — dynamic name, optional `metadata` |
| `spanPure "name" (fun _ => ...)` | profile a **pure** computation from `IO` |
| `timePure "name" (fun _ => ...)` | profile a pure computation from **pure** code |

`profiled` aggregates all calls into one row (static name). For a per-item breakdown — e.g. one row
per layer — use `span` with a runtime name inside your loop:

```lean
for layer in layers do
  h ← span layer.name (metadata := { phase := some "forward" }) do layer.run h
```

## Profiling pure computations

Numeric kernels (matmul, attention, layernorm) are usually **pure**, and that's the one thing naive
timing gets wrong: `span "matmul" (pure (matmul w x))` lets the optimizer float the work *out* of the
span, so it reads ~0 and the cost lands on whatever forces the result later.

Use `spanPure`. It takes a **thunk** and forces it (to WHNF) *inside* the span:

```lean
let h ← spanPure "attention" (fun _ => attention x)
let y ← spanPure "mlp" (metadata := { phase := some "forward" }) (fun _ => mlp h)
```

Two rules:

- **Pass a thunk (`fun _ => ...`), never the value** — `spanPure "k" (kernel x)` evaluates `kernel x`
  before the span even starts.
- Forcing is **WHNF**, which fully evaluates any strictly-built result (`FloatArray`, `Array`, `Nat`,
  strict structs — what real kernels return). Force lazy sub-structure yourself inside the thunk.

For pure call sites you don't want to lift into `IO`, use `timePure` (returns a plain `α`). It records
via unsafe IO, so the compiler may reorder/duplicate/drop the timing and closed-constant expressions
are timed once — prefer `spanPure` whenever you have `IO`. Both are no-ops when profiling is off.

## Explicit interface

For full control, use `LeanProfiler.Runtime` directly:

```lean
def main : IO Unit := do
  clear
  let _ ← recordSpanWith "load.batch"
    { phase := some "input", device := some "cpu" } do
      pure ()   -- work here
  finish .all "build/leanprofiler-trace.json"
```

- `recordSpan "name" do ...` / `recordSpanWith "name" metadata do ...` — time an action and record it.
- `Metadata` is generic (phase, backend, dtype, device, moduleName, shapes, alloc bytes, …). The
  summary groups by a readable label like `forward/cuda/float32/cuda:0/gpt2.block0.attn:matmul`; the
  trace keeps the name and stores the rest under `args`.
- `withStep`/`withModule` add dynamically-scoped context to nested spans; `withParentIndex` links
  cross-task spans (capture `currentSpanIndex` in the parent).
- `recordSpanWithHooks` runs `before`/`after` actions around a span (e.g. a downstream adapter can
  synchronize a CUDA stream and attach allocator stats to the returned metadata).

Output modes: `finish .summary` (table only), `.trace` (Perfetto JSON), `.html`, or `.all`. Open the
JSON in [Perfetto](https://ui.perfetto.dev).

## Demos and tests

```bash
lake exe leanprofiler                             # tiny CPU demo
lake exe structured                               # fake model-style events with metadata
lake exe runtime-checks                           # correctness checks
LEAN_PROFILE=1 lake exe transformer-demo slow     # Example/ case study, baseline
LEAN_PROFILE=1 lake exe transformer-demo fast      # Example/ case study, optimized
```

`runtime-checks` verifies self-time math, hooks, context restoration after failures, concurrent
appends, cross-task parent links, and pure-work attribution.

## What it isn't

Not a Lean *elaboration* profiler (use `set_option profiler`), and not a CUDA/hardware profiler — it
records host-side spans. State is synchronized for concurrent writes; downstream adapters can add
device timelines on top.

## License

Released under the [MIT License](LICENSE).
