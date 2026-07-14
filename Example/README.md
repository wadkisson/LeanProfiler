# Case study: profiling a transformer forward pass

A real forward pass of a small decoder-style transformer, written in plain Lean on `FloatArray`
(embedding, pre-LayerNorm, multi-head attention, GELU MLP, residuals, output projection). No
dependencies — just arithmetic — so the profile is all real Lean runtime.

- `Transformer.lean` — the model and kernels.
- `Main.lean` — the `profiled_main` entry point; the CLI arg picks the activation implementation.

```bash
LEAN_PROFILE=1 lake exe transformer-demo slow    # baseline
LEAN_PROFILE=1 lake exe transformer-demo fast     # the profile-guided fix (identical output)
```

## What the profiler showed

Every kernel is a pure function wrapped in [`spanPure`](../README.md#profiling-pure-computations), so
each is timed correctly. The baseline:

```text
Name                     Self    Calls       %
------------------ ---------- -------- -------
forward:mlp.gelu    231.04 ms        4   49.7%   <-- half the forward pass
forward:mlp.fc1      51.38 ms        4   11.0%
forward:mlp.fc2      47.45 ms        4   10.2%
forward:attn.proj.*  ~26 ms ea       4  ~5.5% ea
forward:attn.core    12.83 ms        4    2.7%
```

The surprise: it's not the matmuls. **GELU — a trivial elementwise activation — is half the forward
pass.** Assume "transformers are matmul-bound" and you'd optimize the 11% while ignoring the 50%.

## The fix

The innocent-looking GELU used a `mut … push` loop, which boxes every computed element:

```lean
def geluSlow : Activation := fun X => Id.run do
  let mut Y := FloatArray.emptyWithCapacity X.size
  for i in [0:X.size] do
    Y := Y.push (geluOf (X.get! i))
  return Y
```

The *same math* with `Array.ofFn` lowers to a tight, unboxed loop:

```lean
def geluFast : Activation := fun X =>
  FloatArray.mk <| Array.ofFn (n := X.size) fun i => geluOf (X.get! i.val)
```

| | GELU kernel | Forward pass |
|---|---|---|
| slow (`mut … push`) | 231 ms | ~465 ms |
| fast (`Array.ofFn`) | 1.35 ms | ~240 ms |
| speedup | **~170x** | **~1.9x** |

The logits checksum is **identical** (`-2.083566`) — same computation, minus the accidental boxing —
and the profile now looks the way a transformer should, with the matmuls on top. Absolute timings
vary by machine; the ranking and ratios reproduce.

## Bonus gotcha

`let model := buildModel …` builds nothing — it's a thunk, and if used from one site the compiler can
recompute the weights on every access (here ~11x slower, outside every span). `loadWeights` forces it
once with `spanPure` — the realistic "load the checkpoint once" step.
