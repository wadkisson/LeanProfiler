# Case study: profiling a transformer forward pass in Lean

This example is a real (inference) forward pass of a small decoder-style transformer, written in
plain Lean on `FloatArray` — token + positional embedding, pre-LayerNorm, multi-head self-attention,
a GELU MLP, residuals, a final norm, and an output projection. No external dependencies, just
arithmetic, so every number you profile is real Lean runtime.

It exists to answer a concrete question: **when my Lean model is slow, where is the time actually
going?** The answer here is not the one you would guess — and that is the whole point of profiling.

- `Example/Transformer.lean` — the model and all kernels.
- `Example/Main.lean` — the entry point (`profiled_main`), selecting the activation implementation.

## Run it

```bash
# Baseline, then the profile-guided fix. Both print the identical logits checksum.
LEAN_PROFILE=1 lake exe transformer-demo slow
LEAN_PROFILE=1 lake exe transformer-demo fast

# Without the env var, it just runs the model — instrumented calls are near-zero overhead.
lake exe transformer-demo fast
```

`LEAN_PROFILE_OUT=build/run.json` controls where the Perfetto trace (`build/run.json`) and the
self-contained HTML report (`build/run.json.html`) are written. Open the JSON in
[ui.perfetto.dev](https://ui.perfetto.dev) for a flame view.

## What the profiler showed

Every kernel is a pure `FloatArray → FloatArray` function wrapped in
[`spanPure`](../README.md#profiling-pure-computations), so its evaluation is forced *inside* its own
span and attributed correctly (a naive `span (pure (kernel x))` would let the optimizer float the
work out and the span would read ~0). Running the baseline:

```text
LEAN_PROFILE=1 lake exe transformer-demo slow

Name                     Self        Total    Calls       %
------------------ ------------ ------------ -------- -------
forward:mlp.gelu      231.04 ms    231.04 ms        4   49.7%   <-- half the forward pass
forward:mlp.fc1        51.38 ms     51.38 ms        4   11.0%
forward:mlp.fc2        47.45 ms     47.45 ms        4   10.2%
forward:attn.proj.k    26.08 ms     26.08 ms        4    5.6%
forward:attn.proj.q    26.00 ms     26.00 ms        4    5.6%
forward:attn.proj.v    25.82 ms     25.82 ms        4    5.5%
forward:attn.proj.o    25.77 ms     25.77 ms        4    5.5%
forward:logits         13.00 ms     13.00 ms        1    2.8%
forward:attn.core      12.83 ms     12.83 ms        4    2.7%
setup:load.weights      2.70 ms      2.70 ms        1    0.5%
```

The surprise: it is not the matmuls. **GELU — a trivial elementwise activation — is 49.7% of the
forward pass**, as expensive as all four attention projections combined. If you had assumed a
transformer is matmul-bound and hand-optimized the matmuls, you would have spent effort on 11% while
ignoring 50%.

## The bug the profiler pointed at

Here is the "obvious", innocent-looking GELU:

```lean
def geluSlow : Activation := fun X => Id.run do
  let mut Y := FloatArray.emptyWithCapacity X.size
  for i in [0:X.size] do
    Y := Y.push (geluOf (X.get! i))   -- boxes every computed element
  return Y
```

The `mut … push` loop looks fine, but it never gives the compiler the tight, unboxed loop it could
have: each computed `Float` is boxed and pushed through a per-iteration closure. Writing the *same
math* with `Array.ofFn`, which lowers to a straight-line unboxed loop, fixes it:

```lean
def geluFast : Activation := fun X =>
  FloatArray.mk <| Array.ofFn (n := X.size) fun i => geluOf (X.get! i.val)
```

## After

```text
LEAN_PROFILE=1 lake exe transformer-demo fast

Name                     Self        Total    Calls       %
------------------ ------------ ------------ -------- -------
forward:mlp.fc1        52.72 ms     52.72 ms        4   22.0%
forward:mlp.fc2        48.47 ms     48.47 ms        4   20.2%
forward:attn.proj.k    26.53 ms     26.53 ms        4   11.0%
forward:attn.proj.o    26.36 ms     26.36 ms        4   11.0%
forward:attn.proj.q    26.33 ms     26.33 ms        4   11.0%
forward:attn.proj.v    26.03 ms     26.03 ms        4   10.8%
forward:logits         13.71 ms     13.71 ms        1    5.7%
forward:attn.core      12.58 ms     12.58 ms        4    5.2%
forward:mlp.gelu        1.35 ms      1.35 ms        4    0.5%   <-- was 231 ms
```

| | GELU kernel | Forward pass (sum of spans) |
|---|---|---|
| slow (`mut … push`) | 231 ms | ~465 ms |
| fast (`Array.ofFn`) | 1.35 ms | ~240 ms |
| speedup | **~170x** | **~1.9x** |

The logits checksum is **identical** in both runs (`-2.083566`) — this is the same computation, just
without the accidental boxing. And the profile now looks the way a transformer *should*: the matmuls
(`fc1`, `fc2`, the projections) are on top, because they are genuinely doing the work.

## Two Lean gotchas this demo also illustrates

- **Pure results are deferred.** `let model := buildModel …` builds nothing — it is a thunk. If it
  is then used from a single site, the compiler can inline it and *recompute the weights on every
  access* deep in the forward pass (here that made the forward ~11x slower, with the cost landing
  outside every span). `loadWeights` forces it once with `spanPure` — the realistic "load the
  checkpoint once" step — so the weights are materialized a single time and shared.
- **Instrumenting pure kernels needs `spanPure`, not `span (pure …)`.** The latter reads ~0 because
  the optimizer floats the evaluation past the timing window. See the
  [pure-profiling section](../README.md#profiling-pure-computations) of the main README.

## Reproducing the numbers

Absolute timings depend on your machine; the *ratios* and the *ranking* are the point, and they
reproduce. The model is deterministic (fixed seed), so the checksum is stable across runs and across
the `slow`/`fast` modes.
