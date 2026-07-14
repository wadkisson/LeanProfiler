# LeanProfiler

A small runtime profiler for compiled Lean programs. Wrap the regions you care about; it times them
and emits a terminal summary, a Chrome/Perfetto trace, and a self-contained HTML report.

Everything is toggled by the `LEAN_PROFILE` environment variable. When it's off, instrumented calls
cost a single boolean check.

## Install

Add it to your `lakefile.toml`, then run `lake update`:

```toml
[[require]]
name = "LeanProfiler"
git = "https://github.com/wadkisson/LeanProfiler"
rev = "main"
```

Use the same toolchain as LeanProfiler (`leanprover/lean4:v4.30.0`, see `lean-toolchain`).

## Two names

There are exactly **two** things to learn:

| Name | Use |
|------|-----|
| `profiled def f := ...` | Profile a whole function (span named after it). On `main`, also clears on entry and writes the report on exit. |
| `span "name" (expr)` | Profile a sub-region — any expression, pure or `IO`. |

That's it. Put the profiler in your project, mark whole functions with `profiled def`, and drop
`span` around anything inside them you want broken out.

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
LEAN_PROFILE=1 lake exe myapp    # records, then writes summary + trace + HTML at exit
lake exe myapp                   # off: instrumented calls are ~no-ops
```

`LEAN_PROFILE` is off when unset/`""`/`"0"`/`"false"`, on otherwise. `LEAN_PROFILE_OUT` sets the
trace path (default `build/leanprofiler-trace.json`); the HTML report is that path + `.html`.

## Whole functions

Change `def` to `profiled def`. That's the only edit — the body stays the same. Every call
contributes to one summary row named after the function.

**Before:**

```lean
def loadBatch (n : Nat) : IO (Array Nat) :=
  pure (Array.range n)

def matmul (w x : FloatArray) : FloatArray :=
  -- kernel body
  x

def main : IO Unit := do
  let data ← loadBatch 1024
  IO.println s!"loaded {data.size} items"
```

**After:**

```lean
import LeanProfiler
open LeanProfiler

profiled def loadBatch (n : Nat) : IO (Array Nat) :=
  pure (Array.range n)

profiled def matmul (w x : FloatArray) : FloatArray :=
  -- kernel body — unchanged
  x

profiled def main : IO Unit := do
  let data ← loadBatch 1024
  IO.println s!"loaded {data.size} items"
```

On `main`, `profiled def` also handles setup and teardown: it clears profiler state on entry and
writes the summary, trace, and HTML report on exit. You don't call `clear` or `finish` yourself.

## Sub-regions

Wrap the expression you want timed with `span "name" (...)`. The code inside the parentheses is
unchanged — pure kernels and `IO` actions use the same syntax.

**Before:**

```lean
def forward (model : Model) (x : FloatArray) : IO FloatArray := do
  let normed ← pure (layerNorm x)
  let attn   ← pure (attention normed)
  let hidden ← pure (mlp attn)
  pure hidden

def main : IO Unit := do
  let model ← buildModel
  let mut x := embedTokens model tokens
  for i in [0:model.blocks.size] do
    x ← blockForward model.blocks[i]! x
  IO.println s!"done: {x.size} activations"
```

**After:**

```lean
def forward (model : Model) (x : FloatArray) : IO FloatArray := do
  let normed ← span "ln"   (layerNorm x)
  let attn   ← span "attn" (attention normed)
  let hidden ← span "mlp"  (mlp attn)
  pure hidden

profiled def main : IO Unit := do
  let model ← span "load.weights" (buildModel)
  let mut x := embedTokens model tokens
  for i in [0:model.blocks.size] do
    x ← span s!"block{i}" (blockForward model.blocks[i]! x)
  IO.println s!"done: {x.size} activations"
```

Each `span` adds a row to the report. Use a runtime name like `s!"block{i}"` when you want one row
per loop iteration instead of one aggregated row.

### Why pure work needs no special wrapper

Naive timing gets pure code wrong: `span "matmul" (pure (matmul w x))` can let the optimizer float
the work *out* of the span. `span` avoids this automatically — it forces pure expressions inside
the timed region via `IO.lazyPure`, so numeric kernels (matmul, attention, layernorm) are attributed
correctly. Just write the expression normally; don't wrap it in `fun _ => ...`.

## Putting it together

The before/after sections above combined — a model-style forward pass with per-kernel and per-block
breakdown:

```lean
import LeanProfiler
open LeanProfiler

def layerNorm (x : FloatArray) : FloatArray := ...
def attention (x : FloatArray) : FloatArray := ...
def mlp       (x : FloatArray) : FloatArray := ...

def blockForward (blk : Block) (x : FloatArray) : IO FloatArray := do
  let normed ← span "ln"   (layerNorm x)
  let attn   ← span "attn" (attention normed)
  let hidden ← span "mlp"  (mlp attn)
  pure hidden

profiled def main : IO Unit := do
  let model ← span "load.weights" (buildModel)
  let mut x := embedTokens model tokens
  for i in [0:model.blocks.size] do
    x ← span s!"block{i}" (blockForward model.blocks[i]! x)
  IO.println s!"done: {x.size} activations"
```

```bash
LEAN_PROFILE=1 lake exe myapp
```

The summary ranks spans by self-time, so a surprise bottleneck shows up immediately rather than
being hidden behind the matmuls you assumed were the cost.

## Advanced: metadata and manual control

Need per-span metadata (phase, device, shapes) or hooks for CUDA sync / allocator stats? Drop down
to `LeanProfiler.Runtime`:

```lean
let _ ← recordSpanWith "matmul"
  { phase := some "forward", device := some "cuda:0" } do
    ...
```

Or call `spanCore` directly (same as `span`, but accepts a `Metadata` argument):

```lean
spanCore "matmul" (matmul w x) { phase := some "forward" }
```

Other Runtime helpers:

- `clear` / `finish .summary | .trace | .html | .all` — lifecycle and output.
- `withStep` / `withModule` — add dynamically-scoped context to nested spans.
- `withParentIndex` — link cross-task spans (capture `currentSpanIndex` in the parent).
- `recordSpanWithHooks` — run `before`/`after` actions around a span.

Open the Perfetto JSON in [Perfetto](https://ui.perfetto.dev).

## Demos and tests

```bash
lake exe leanprofiler                             # tiny CPU demo
lake exe structured                               # fake model-style events with metadata
lake exe runtime-checks                           # correctness checks
```

`runtime-checks` verifies self-time math, hooks, context restoration after failures, concurrent
appends, cross-task parent links, and pure-work attribution.

## What it isn't

Not a Lean *elaboration* profiler (use `set_option profiler`), and not a CUDA/hardware profiler —
it records host-side spans. State is synchronized for concurrent writes; downstream adapters can add
device timelines on top.

## License

Released under the [MIT License](LICENSE).
