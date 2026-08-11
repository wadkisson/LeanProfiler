/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

import VersoManual
import LeanProfiler

open Verso.Genre Manual

#doc (Manual) "How a span becomes a report" =>
%%%
tag := "how-it-works"
%%%

The public API makes profiling look like one function call:

```
span "source.analyze" (analyzeSource source)
```

That small boundary is intentional. The application already knows that this action is source
analysis; the profiler should preserve that fact without asking the caller to manage clocks,
thread stacks, or report files. Internally, the span passes through four distinct stages:

```
reserve its place in the event tree
sample time and Lean heartbeats around the action
complete and retain an event
analyze all retained events when the session ends
```

Keeping these stages separate is what lets the same capture handle nested calls, worker threads,
asynchronous runtimes, and repeated measurements without changing the basic `span` API.

# The session owns the capture
%%%
tag := "session-capture"
%%%

`profile` starts one process-wide recording session. It resets the event buffer, records a process
snapshot, enables instrumentation, and opens the root span. When the action finishes, it disables
new recording before analyzing and exporting the completed events.

The process-wide ownership is deliberate. A report needs one index space and one unambiguous set of
output paths. Nested spans are ordinary events, but a second overlapping `profile` session is
rejected rather than allowed to compete for the same buffer.

If profiling is disabled, `profileFromEnvironment` still runs the action and `span` does not retain
an event. This keeps instrumentation in normal application code instead of requiring a separate
profiling build.

# Reservation establishes the event tree
%%%
tag := "span-reservation"
%%%

Before the timed action starts, LeanProfiler reserves an event index under a mutex. The reservation
reads the current Lean thread identifier and the innermost active span on that thread. It records:

:::table +header
*
  * Field
  * Meaning at reservation time
*
  * `index`
  * a monotonically increasing event identifier
*
  * `parentIndex`
  * the active local parent, or an explicitly supplied cross-thread parent
*
  * `depth`
  * the event's nesting depth in the logical tree
*
  * `threadId`
  * the Lean execution thread that admitted the span
*
  * inherited metadata
  * dynamic phase, module, step, and related context
:::

The index is reserved before the action because completion order is not execution order. A short
child may finish before its parent, and two worker threads may finish in either order. Export sorts
events by their reservation indices, while every event also keeps its actual start and stop times.

Each Lean thread has its own nesting stack. This prevents concurrent work from becoming accidental
siblings or children merely because another thread happened to open a span first. When a caller
spawns a worker, it can explicitly pass the current parent index to that worker; the trace then
keeps the causal link without pretending that the two threads share one clock.

# The timed interval has a precise boundary
%%%
tag := "timed-interval"
%%%

Once reservation is complete, the profiler samples `IO.monoNanosNow` and
`IO.getNumHeartbeats`, runs the action, and samples both again. The resulting event stores elapsed
monotonic host time and the difference in Lean heartbeats.

These measurements answer different questions. Host time includes waiting, scheduling, operating
system work, and synchronous foreign calls. Lean heartbeats are a runtime work counter associated
with the current Lean thread. They are not CPU cycles, allocation bytes, or a device timer. A phase
whose host time rises while its heartbeat count stays nearly fixed is often waiting or doing work
outside ordinary Lean execution; a phase whose two measurements rise together is more likely doing
additional Lean-side work.

The action is protected by `try`/`finally`. Its event is completed and the thread stack is restored
even when it throws. The original exception then continues to the caller. This matters in practice:
a partial trace from a failed run is often the clearest record of where the failure occurred.

# Hooks define when asynchronous work is finished
%%%
tag := "span-hook-boundary"
%%%

A host call can return before a GPU, accelerator, or foreign task has completed. Stopping the clock
at that return would measure submission latency rather than completed work. `SpanHooks` lets an
adapter define the boundary without putting CUDA, PyTorch, or another runtime into the core
package:

```
prepare
  start clock
    run action
    completeTiming
  stop clock
enrich metadata
```

`prepare` creates adapter state before timing. `completeTiming` may synchronize the selected
runtime before the stop sample. `enrich` runs outside the measured interval and can attach allocator
or device counters. The metadata should name the timing convention because a synchronized device
span and an unsynchronized host-launch span answer different questions.

The hook does not expose the kernels or operators inside a foreign call. It gives the outer Lean
application an honest completion boundary. PyTorch Profiler, Nsight, Perfetto, or another
runtime-specific tool remains the right instrument when the question lies below that boundary.

# Analysis computes inclusive and self time
%%%
tag := "event-analysis"
%%%

After the session closes, `analyze` first sorts the events by reservation index and validates their
structure. It checks duplicate indices, missing parents, impossible depths, reversed intervals, and
child intervals that extend outside their parents. Validation issues remain in the report instead
of being silently repaired into benchmark data.

For an event with interval `I`, inclusive time is simply the length of `I`. Self time removes
the portion covered by its immediate children on the same thread:

$$`t_{\mathrm{self}}(e)
  = |I_e| - \left|\bigcup_{c \in C_e} (I_c \cap I_e)\right|`

The union is important. If malformed or overlapping child intervals cover the same nanoseconds,
those nanoseconds are subtracted once, not once per child. Intervals are clipped to the parent, and
subtraction is bounded so a diagnostic report cannot contain self time larger than inclusive time.

Cross-thread children are not subtracted. Two threads may run simultaneously, so removing a worker
thread's elapsed interval from its caller would confuse a causal relationship with exclusive time
on one clock. The parent link remains available in the trace for correlation.

Heartbeats follow the same parent rule when a same-thread child lies completely inside its parent.
The analysis layer proves that every emitted timing has self time no greater than inclusive time,
and likewise for heartbeats.

# Repeated spans become summary rows
%%%
tag := "summary-grouping"
%%%

Individual events remain in the timeline. For comparison, repeated events are grouped by a stable
structured key:

```
name, phase, activity, backend, dtype, device, module
```

Step numbers and shape arrays remain event metadata, so a thousand training steps do not turn into
a thousand unrelated rows. Each group records call count, total inclusive and self time,
minimum, mean, median, nearest-rank p95, maximum, heartbeat totals, and any memory counters supplied
by an adapter.

This produces two complementary artifacts. The Trace Event file preserves temporal order and opens
in Perfetto. The strict summary JSON preserves grouped measurements and validation state for scripts,
CI, and baseline comparisons. The trace helps explain a run; the summary makes a repeated change
measurable.

# What LeanProfiler does not infer
%%%
tag := "profiler-limits"
%%%

LeanProfiler does not sample the native call stack, discover every function, intercept allocations,
or recognize model operators automatically. Those jobs require compiler instrumentation, operating
system sampling, or runtime-specific support. Instead, LeanProfiler records application boundaries
chosen by the Lean program and gives adapters a typed place to add measurements they can justify.

This choice is useful when a program crosses several systems. A span can retain the name
`training.step` or `solver.expand` while a lower-level profiler explains what happened inside one
particular call. It also means that span placement is part of the experiment: begin with broad
phases, inspect the first trace, and add detail only where the next question requires it.

Enabled profiling has real overhead: mutex access, clock and heartbeat samples, event storage, and
eventual analysis. It is designed for selected runtime phases rather than tracing every arithmetic
operation. Scheduled captures, stable span names, and a finite event limit keep that cost visible
and controlled.
