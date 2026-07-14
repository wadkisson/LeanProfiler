# LeanProfiler

LeanProfiler is a small runtime profiler for executable Lean programs. It records host-side spans
with structured metadata, then emits a terminal summary, a Chrome/Perfetto trace, and a
self-contained HTML report.

There are two ways to use it:

- **Simple interface** (`LeanProfiler.Sugar`): mark functions with `profiled`, mark your entry
  point with `profiled_main`, and toggle everything at runtime with the `LEAN_PROFILE` environment
  variable. When profiling is off, instrumented calls degrade to a single boolean check.
- **Explicit interface** (`LeanProfiler.Runtime`): call `recordSpanWith`, `withStep`, `withModule`,
  hooks, and `finish` directly. Use this when you want structured metadata, precise span boundaries,
  or a downstream runtime adapter.

Both share the same core: `clear` at the start, spans in the middle, `finish` at the end.

## Install

Add LeanProfiler to your project's `lakefile.toml`:

```toml
[[require]]
name = "LeanProfiler"
git = "https://github.com/wadkisson/LeanProfiler"
rev = "main"
```

Or depend on a local checkout:

```toml
[[require]]
name = "LeanProfiler"
path = "../LeanProfiler"
```

Then run `lake update`. Your project must use the same Lean toolchain as LeanProfiler
(`leanprover/lean4:v4.30.0`, see `lean-toolchain`).

```lean
import LeanProfiler
open LeanProfiler
```

## Simple Interface

The entire user-facing surface is four names:

| Name | Use |
|------|-----|
| `profiled_main def main := ...` | entry point: `clear` on entry, `finish .all` on exit |
| `profiled def f := ...` | record a span named after the function |
| `span "name" do ...` | record a span with a runtime-chosen name (loops, per layer) |
| `spanWith "name" meta do ...` | same, with structured metadata (shapes, phase, memory) |

One rule to remember: **wrap `main` in `profiled_main`, mark work with `profiled` / `span`, run with
`LEAN_PROFILE=1`.** The span name for `profiled` is taken from the declaration name.

```lean
import LeanProfiler

profiled def loadBatch (n : Nat) : IO (Array Nat) := do
  pure (Array.range n)

profiled_main def main : IO Unit := do
  let _ ← loadBatch 1024
  pure ()
```

Toggle profiling at runtime — no code changes:

```bash
LEAN_PROFILE=1 lake exe myapp    # records, then writes summary + trace + HTML at exit
lake exe myapp                   # profiling off: instrumented calls are ~no-ops
```

- `LEAN_PROFILE` — unset, `""`, `"0"`, or `"false"` means off; anything else means on.
- `LEAN_PROFILE_OUT` — trace output path (default `build/leanprofiler-trace.json`). The HTML report
  is written to that path followed by `.html`.

`profiled` names spans by the (static) function name, so all calls aggregate into one row. For a
per-item breakdown — e.g. one row per layer of a model — use `span` with a runtime-chosen name inside
the dispatch loop:

```lean
-- a model is data: `span layer.name` gives one row per layer, for free
def forward (layers : Array Layer) (x : Tensor) : IO Tensor := do
  let mut h := x
  for layer in layers do
    h ← spanWith layer.name { phase := some "forward" } do layer.run h
  return h
```

`span` / `spanWith` are gated on `LEAN_PROFILE` exactly like `profiled`, so leaving them in production
code costs a single boolean check when profiling is off. They only emit output when the entry point
is wrapped in `profiled_main` (which owns `clear` / `finish`).

## Explicit Interface

For full control, instrument the boundaries you care about directly: an `IO` block, a model step, an
operator dispatch, or a downstream runtime adapter.

```lean
import LeanProfiler

open LeanProfiler

def main : IO Unit := do
  clear
  let _ ← recordSpanWith "load.batch"
    { phase := some "input", backend := some "lean", device := some "cpu" } do
      -- work here
      pure ()
  finish .all "build/leanprofiler-trace.json"
```

`recordSpan "name" do ...` is the no-metadata form; `recordSpanWith "name" metadata do ...` attaches
structured metadata. Both run the action, time it, record a span, and return the action's result.

`finish .all ...` prints a terminal summary and writes:

```text
build/leanprofiler-trace.json
build/leanprofiler-trace.json.html
```

Open the JSON trace in [Perfetto](https://ui.perfetto.dev). The HTML report is self-contained and
useful for quick review.

## Structured Metadata

The metadata is deliberately generic. TorchLean can use it for model runtime events, but the package
does not depend on TorchLean.

```lean
let metadata : Metadata :=
  { phase := some "forward",
    backend := some "cuda",
    dtype := some "float32",
    device := some "cuda:0",
    moduleName := some "gpt2.block0.attn",
    graphNode := some "node_17",
    stepIndex := some 0,
    inputShapes := #["[2,64,32]", "[32,32]"],
    outputShape := some "[2,64,32]",
    allocLiveBytes := some 1048576,
    allocPeakBytes := some 2097152 }

let _ ← recordSpanWith "matmul" metadata do
  pure ()
```

The terminal summary groups events using readable labels like:

```text
forward/cuda/float32/cuda:0/gpt2.block0.attn:matmul
```

The trace keeps the event name as `matmul`, uses the phase as the trace category, and stores the
rest under `args`.

## Context

Use context when many nested spans belong to the same step or module.

```lean
withStep 0 do
  withModule "demo.mlp" do
    let _ ← recordSpanWith "linear" { phase := some "forward" } do
      pure ()
```

The context is dynamically scoped and restored with `try/finally`, so failed actions do not poison
later events.

For asynchronous work, capture the current span and pass it into the task explicitly:

```lean
recordSpan "parent" do
  if let some parent ← currentSpanIndex then
    let task ← IO.asTask do
      withParentIndex parent do
        recordSpan "child" do
          pure ()
    match task.get with
    | Except.ok () => pure ()
    | Except.error error => throw error
```

Events store both a `threadId` and a `parentIndex`. Normal nested spans get parent links
automatically. Cross-task spans can use `withParentIndex` when the caller wants one logical tree.

## Runtime Hooks

Use hooks when a downstream project needs to do work around the measured span. For example,
TorchLean can synchronize a CUDA stream before and after an op, then attach allocator stats to the
metadata returned by `after`.

```lean
let hooks : SpanHooks :=
  { before := pure () -- downstream adapter can synchronize here
    after := fun metadata =>
      pure { metadata with timing := some "device-synchronized" } }

let _ ← recordSpanWithHooks "matmul" { phase := some "forward" } hooks do
  pure ()
```

This keeps LeanProfiler generic. The package owns event recording, summaries, JSON, and HTML.
TorchLean or another runtime owns CUDA, tensor shapes, allocator snapshots, and framework-specific
labels.

## Output Modes

```lean
finish .summary "build/ignored.json" -- terminal table only
finish .trace   "build/run.json"     -- Perfetto/Chrome JSON only
finish .html    "build/run.json"     -- self-contained HTML only
finish .all     "build/run.json"     -- summary + JSON + HTML
```

## Smoke Tests

```bash
lake build LeanProfiler
lake exe leanprofiler
lake exe structured
lake exe runtime-checks
```

`leanprofiler` runs a tiny CPU demo. `structured` emits fake model-style events with shape and
device metadata. `runtime-checks` verifies the summary self-time calculation, hook metadata,
context restoration after a failed span, concurrent event appends, independent per-thread nesting,
and explicit cross-task parent links.

## What This Is Not

LeanProfiler is not a Lean elaborator profiler. Lean already has tools for elaboration and
heartbeat-level work.

LeanProfiler is also not a CUDA profiler by itself. It records host-side spans. Downstream packages
such as TorchLean can add CUDA synchronization, allocator stats, or device events in an adapter
without putting those dependencies in this package.

The runtime state is synchronized so concurrent writes do not corrupt the event log. Parent links
are tracked per runtime thread, and cross-task parentage can be passed explicitly. That still does
not make LeanProfiler a replacement for CUPTI or hardware device timelines; it is the generic
host-side layer that those adapters can feed.
