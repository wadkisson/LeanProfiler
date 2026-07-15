# TorchLean MLP Profile

This optional package profiles TorchLean training without making TorchLean a dependency of the core
LeanProfiler library. The model is shape-checked in Lean, while its width, depth, batch size,
optimizer, scalar representation, backend, and device are runtime choices.

The defaults describe a five-hidden-layer MLP with 100,687,872 trainable parameters. Build it with
TorchLean's CUDA runtime and launch the full GPU stress workload:

```bash
lake -R -K cuda=true build torchlean-mlp-profile

LEAN_PROFILE=1 LEAN_PROFILE_OUT=build/torchlean-mlp-100m.json \
  lake -R -K cuda=true exe torchlean-mlp-profile --device cuda
```

For a short CPU smoke test, use the same executable with smaller dimensions:

```bash
LEAN_PROFILE=1 LEAN_PROFILE_OUT=build/torchlean-mlp-cpu.json \
  lake exe torchlean-mlp-profile --device cpu \
    --input 128 --hidden 256 --layers 3 --output 64 --batch 8 --steps 2
```

No architecture is fixed in the profiler integration. `--input`, `--hidden`, `--layers`,
`--output`, and `--batch` determine the typed model and generated dataset together. Run
`lake exe torchlean-mlp-profile --help` for the complete workload and TorchLean runtime options.

The 100M configuration is a scaling workload rather than a quick-start test. Use the smaller CPU
command when checking an installation, then increase the dimensions or number of steps when you
want a longer profile. No source changes are needed: the model, generated data, and profiler
metadata all follow the command-line dimensions.

The trace contains separate training and post-training inference spans, including model shape,
parameter scale, device, backend, and scalar metadata. LeanProfiler writes the
Chrome/Perfetto-compatible JSON trace and a self-contained HTML report beside it.
