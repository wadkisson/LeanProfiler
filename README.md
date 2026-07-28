# LeanProfiler

A Lean executable can be slow for reasons the compiler never sees: a data loader stalls, one phase
of a training loop grows, a foreign call blocks, or an accelerator finishes later than its launch.
A stopwatch around the whole command confirms the delay but does not locate it.

LeanProfiler lets the running program mark boundaries such as `batch.load`, `model.forward`, and
`optimizer.step`. Each capture produces:

- a Trace Event file that opens in [Perfetto](https://ui.perfetto.dev);
- a strict JSON summary with integer-nanosecond timings, grouped rows, heartbeats, and process
  counters.

The trace preserves order, nesting, threads, and metadata. The summary aggregates repeated work and
can compare a candidate run against a baseline.

![A LeanProfiler investigation from a performance question to a diagnosis or regression gate](guide/LeanProfilerGuide/Assets/profiling-workflow.svg)

## Add it to a project

```toml
[[require]]
name = "LeanProfiler"
git = "https://github.com/lean-dojo/LeanProfiler"
rev = "main"
```

Wrap the work you want to measure:

```lean
import LeanProfiler

open LeanProfiler

def main : IO Unit :=
  profileFromEnvironment "application" do
    span "batch.load" loadBatch
    span "model.forward" forward (metadata := {
      phase := some "forward"
      backend := some "eager"
      dtype := some "float32"
      device := some "cpu"
    })
```

Run it with profiling enabled:

```sh
LEAN_PROFILE=1 lake exe your_executable
```

The default files are:

```text
build/leanprofiler-trace.json
build/leanprofiler-summary.json
```

Use `LEAN_PROFILE_OUT` and `LEAN_PROFILE_SUMMARY_OUT` to keep several runs.
`LEAN_PROFILE_MAX_EVENTS` bounds long captures, and `LEAN_PROFILE_PROCESS_NAME` changes the process
label shown in Perfetto.

Without `LEAN_PROFILE=1`, the same action runs without retaining spans or writing reports.

The umbrella import contains the runtime API, report writers, schedules, and summary comparison.
Three narrower features use explicit imports:

```lean
import LeanProfiler.Syntax  -- `profiled def`
import LeanProfiler.CLI     -- embeddable command router
import LeanProfiler.Proofs  -- laws about schedules, comparisons, and timing analysis
```

Most applications need only `import LeanProfiler`. Keeping the command syntax separate avoids
loading Lean's compiler front end into an ordinary runtime executable.

## Try the examples

```sh
LEAN_PROFILE=1 lake exe leanprofiler_nested_example
LEAN_PROFILE=1 lake exe leanprofiler_async_example
LEAN_PROFILE=1 lake exe leanprofiler_schedule_example
lake exe leanprofiler_regression_example
```

The examples cover nested metadata, asynchronous completion, scheduled active steps, and a complete
baseline-to-regression walkthrough.

## What the output looks like

![A nested timeline with one root span and alternating input.load and model.forward child spans](guide/LeanProfilerGuide/Assets/nested-spans-timeline.svg)

The timeline shows the order, duration, and nesting of every recorded span.

![A paired-dot plot comparing baseline and candidate p95 values for three rows](guide/LeanProfilerGuide/Assets/p95-comparison.svg)

The comparison plot makes changed p95 timings visible before you inspect the JSON report.

## Compare summaries

```sh
lake exe leanprofiler compare \
  build/baseline-summary.json \
  build/candidate-summary.json \
  --metric p95_ns \
  --absolute-tolerance 500000 \
  --relative-tolerance-bps 1000 \
  --json build/comparison.json
```

A candidate increase is a regression only when it exceeds both tolerances. New and missing keys
are reported separately. Invalid or incomplete summaries are rejected unless the caller requests a
diagnostic comparison.

## TorchLean

TorchLean programs can import the core package directly. A separate package contains a command
runner and MLP training walkthrough:

```sh
cd integrations/TorchLean
lake build
lake test
LEAN_PROFILE=1 lake exe leanprofiler_torchlean_mlp
```

The runner also has a CUDA adapter. It rejects CPU parity stubs, waits for the selected device
before closing the command span, and records TorchLean device-buffer counters:

```sh
LEAN_PROFILE=1 \
lake -R -K cuda=true exe leanprofiler_torchlean \
  quickstart_mlp --device cuda --steps 3
```

See [the integration README](integrations/TorchLean/README.md).

## Guide

The [published Verso guide](https://lean-dojo.github.io/LeanProfiler/) follows one real slowdown
investigation from instrumentation through its timeline, summary, diagnosis, and regression check.
It also explains sessions, hooks, repeated capture schedules, Lean's elaboration profilers,
PyTorch Profiler, and TorchLean on CPU and CUDA.

Build it locally:

```sh
cd guide
lake exe leanprofiler-guide-assets
lake exe leanprofiler-guide --output build/guide
```

The rendered site is under `guide/build/guide/html-multi`.

The checked-in JSON captures are real observations. The SVG figures are regenerated from those
artifacts by Lean code.

## Tests

```sh
lake test
lake lint
```

The TorchLean package has its own test driver under `integrations/TorchLean`.

## Team and license

Maintained by the LeanProfiler Team. Released under the [MIT license](LICENSE).
