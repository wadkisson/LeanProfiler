/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

import VersoManual

open Verso.Genre Manual

#doc (Manual) "Choose the right profiler" =>
%%%
tag := "profiler-comparison"
%%%

A model command can be slow in three distinct places. Lean may spend time elaborating and compiling
the program. The running application may spend time loading data, building a graph, or waiting at a
foreign boundary. A framework or accelerator may spend time in operators, memory copies, and
kernels. No single profiler sees all three.

![The observation boundaries of Lean profiling tools, LeanProfiler, and PyTorch Profiler](../../Assets/profiler-scope.svg)

The views can support one investigation, but their events and timing columns answer different
questions.

# Before `main`: Lean's profilers
%%%
tag := "lean-elaboration-profilers"
%%%

Use Lean's command-line profile when a declaration makes a file slow to build:

```
lake env lean --profile MyProject/SlowModule.lean
```

It reports elaboration and type-checking time by declaration. Use it when an import or theorem
became expensive before the executable starts.

The component profiler accumulates exclusive time inside instrumented elaborator and compiler
components:

```
lake env lean \
  -Dprofiler=true \
  -Dprofiler.threshold=10 \
  MyProject/SlowModule.lean
```

The threshold is in milliseconds. The default is 100 milliseconds.

`trace.profiler` keeps Lean's nested trace tree and can export a
Firefox-Profiler-compatible file:

```
lake env lean \
  -Dtrace.profiler=true \
  -Dtrace.profiler.threshold=5 \
  -Dtrace.profiler.output=build/elaboration-profile.json \
  MyProject/SlowModule.lean
```

With `-Dtrace.profiler.useHeartbeats=true`, its measurement and threshold use heartbeats.
`trace.profiler.serve` starts an ephemeral loopback server and opens Firefox Profiler. The server
shuts down after the profile is fetched.

Two smaller tools answer local questions:

- `IO.timeit` prints elapsed time for one `IO` action;
- `IO.allocprof` invokes Lean's runtime allocation-profiler hook.

These tools do not replace an application runtime profile. A file can elaborate quickly while its
executable spends minutes in a training loop.

# After `main`: LeanProfiler
%%%
tag := "runtime-measurement-sources"
%%%

LeanProfiler measures boundaries chosen by the Lean application. A training loop can use names that
do not exist inside the compiler or a foreign framework:

```
profileFromEnvironment "training" do
  for step in List.range steps do
    withStep step do
      span "batch.load" loadBatch
      span "model.forward" forward
      span "loss.backward" backward
      span "optimizer.step" optimizerStep
```

Its measurements come from Lean and `Std` runtime APIs:

- `IO.monoNanosNow` for monotonic span boundaries;
- `IO.getTID` for the current Lean thread;
- `IO.Process.getPID` for Trace Event process identity;
- `IO.getNumHeartbeats` for the current thread's work counter;
- `Std.IO.Process.getResourceUsage` for session-wide process counters.

Heartbeats add a Lean-specific signal alongside elapsed time. LeanProfiler does not discover
operations by itself: the application decides where a span begins, what it is called, and which
metadata it carries.

None of these APIs produces accelerator kernel timestamps. A completion hook can synchronize a
device and attach allocator counters, but an absent field means “not observed,” not zero.

# Inside PyTorch: PyTorch Profiler
%%%
tag := "pytorch-comparison"
%%%

PyTorch Profiler instruments the framework and supported device runtime. A typical training capture
selects activities, excludes startup with a schedule, labels one application range, advances the
schedule after each step, prints operator aggregates, and exports a trace:

```
import torch
from torch.profiler import ProfilerActivity, profile, record_function

activities = [ProfilerActivity.CPU]
if torch.cuda.is_available():
    activities.append(ProfilerActivity.CUDA)

def save_trace(prof):
    print(prof.key_averages().table(
        sort_by="self_cpu_time_total",
        row_limit=20,
    ))
    prof.export_chrome_trace(f"trace-{prof.step_num}.json")

with profile(
    activities=activities,
    schedule=torch.profiler.schedule(
        wait=1, warmup=1, active=3, repeat=1
    ),
    on_trace_ready=save_trace,
    record_shapes=True,
    profile_memory=True,
    with_stack=True,
) as prof:
    for batch in loader:
        with record_function("training.step"):
            loss = model(batch)
            loss.backward()
            optimizer.step()
            optimizer.zero_grad()
        prof.step()
```

The user range is only one event in this capture. PyTorch can also record framework operators and
supported runtime activity below it. With CUDA activity enabled, its Kineto integration uses CUPTI
where available to add runtime calls and on-device kernels to the trace. Other supported builds may
offer XPU or additional accelerator activity; `torch.profiler.supported_activities()` reports what
the current installation exposes.

`record_shapes`, `profile_memory`, `with_stack`, and `with_flops` answer different questions and all
have costs. Shape recording can retain tensor references and affect optimizations. Stack collection
adds source information but increases overhead. FLOP estimates cover selected operators rather
than arbitrary code. Start with the smallest feature set that answers the question.

# Similar controls, different observations
%%%
tag := "profiler-capability-table"
%%%

Both profilers name ranges, aggregate repeated work, schedule short captures inside long loops, and
export a timeline. What creates an event is different:

:::table +header
*
  * Capability
  * LeanProfiler
  * PyTorch profiler
*
  * Primary boundary
  * running Lean application
  * PyTorch framework and supported device runtime
*
  * User-defined range
  * `span` or `profiled def`
  * `record_function`
*
  * Capture boundary
  * `profile` or `profileFromEnvironment`
  * `torch.profiler.profile`
*
  * Long-run schedule
  * skip, warmup, record, record-and-save
  * `NONE`, `WARMUP`, `RECORD`, `RECORD_AND_SAVE`, advanced by `step()`
*
  * Automatic operation events
  * none
  * PyTorch operators and selected runtime activity
*
  * Accelerator timing
  * host timing; an adapter may synchronize the device
  * supported device activities, including CUDA kernels when CUPTI is available
*
  * Shapes
  * application-supplied metadata
  * optional operator input shapes
*
  * Memory
  * process resources; allocator adapters may supply span counters
  * optional tensor allocation, release, and memory timeline data
*
  * Stacks and FLOPs
  * not collected automatically
  * optional source stacks and estimates for selected operators
*
  * Aggregation
  * structured key plus min, mean, median, p95, max, self, and total
  * `key_averages`, optionally grouped by shape, stack, or overload
*
  * Lean-specific signal
  * heartbeats
  * none
*
  * Trace export
  * Trace Event JSON for Perfetto
  * Chrome Trace JSON; TensorBoard trace handler is also available
*
  * Built-in regression input
  * strict versioned summary and built-in comparison
  * the user or surrounding tooling defines the gate
:::

LeanProfiler is not a smaller reimplementation of PyTorch Profiler. It adds an application-level
view for Lean programs, including code that never enters PyTorch. PyTorch Profiler supplies the
deeper operator and device view when the work is inside PyTorch.

# Read the timing columns carefully
%%%
tag := "timing-semantics-comparison"
%%%

LeanProfiler's total duration is the host interval from the start of a span to its end. Self time
subtracts immediate same-thread child coverage. A synchronized CUDA hook makes that host interval
wait for device completion, but it still does not become a sum of kernel durations.

PyTorch tables separate CPU and supported device measurements. A user range can have CPU total,
CPU self, and device-related columns derived from events correlated below it. Sorting by
`self_cpu_time_total` answers a different question from sorting by `self_cuda_time_total`.

Neither table should be treated as hardware utilization. Overlap, asynchronous launches, multiple
threads, multiple streams, and profiler overhead all matter. Warm up first, keep synchronization
policy fixed, and compare the same columns under the same configuration.

PyTorch's schedule also has details absent from LeanProfiler's current `Schedule`, including
`skip_first_wait`. LeanProfiler's `runScheduledCycle` runs waiting and warmup callbacks before
opening each active session. PyTorch keeps the profiler object around the loop and `step()` advances
its internal state.

# Use both around a foreign boundary
%%%
tag := "foreign-runtime-boundary"
%%%

A Lean program calling PyTorch or LibTorch can place a LeanProfiler span around the foreign call
and start the framework profiler inside that runtime. The outer span answers how long the Lean
caller waited and how the call fits among surrounding application phases. The inner trace explains
the operators and supported device activity responsible for that interval.

Correlating the files requires a shared identifier or timestamp convention supplied by the
adapter. Two unrelated timelines should not be aligned by eye and presented as one clock.

# Start with the symptom
%%%
tag := "profiler-choice"
%%%

:::table +header
*
  * Symptom
  * First tool
  * Why
*
  * one Lean declaration is slow to build
  * `lean --profile` or `trace.profiler`
  * the cost occurs during elaboration or compilation
*
  * a running Lean command has a slow phase
  * LeanProfiler
  * the application owns the meaningful phase names
*
  * a PyTorch operator dominates CPU time
  * PyTorch Profiler
  * operators are discovered and grouped automatically
*
  * a CUDA model waits unexpectedly
  * LeanProfiler boundary plus PyTorch/CUPTI or Nsight detail
  * one view locates the application call; the other resolves kernels and runtime activity
*
  * a candidate build regressed
  * LeanProfiler comparison over repeated controlled captures
  * the summary schema and threshold policy are explicit
:::

# References
%%%
tag := "profiler-references"
%%%

- Lean,
  [`Lean.Util.Profiler` API](https://lean-lang.org/doc/api/Lean/Util/Profiler.html).
- Lean,
  [Lean 4.31 profiler release note](https://lean-lang.org/doc/reference/latest/releases/v4.31.0/).
- PyTorch,
  [`torch.profiler` reference](https://docs.pytorch.org/docs/stable/profiler.html).
- PyTorch,
  [profiler recipe](https://docs.pytorch.org/tutorials/recipes/recipes/profiler_recipe.html).
- PyTorch,
  [profiling a module](https://docs.pytorch.org/tutorials/beginner/profiler.html).
- Perfetto,
  [Trace Event format](https://perfetto.dev/docs/getting-started/other-formats).
