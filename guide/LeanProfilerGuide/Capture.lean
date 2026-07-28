/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

import VersoManual
import LeanProfiler

open Verso.Genre Manual

#doc (Manual) "Design the capture" =>
%%%
tag := "capture"
%%%

The first trace separated input loading from the model's forward pass. That was enough to locate
the larger interval, but not enough to compare different steps, modules, devices, or backends. The
next capture should add that context without turning every observation into a different event.

Suppose the measured loop looks like this:

```
let mut parameters := initialParameters
for step in List.range steps do
  let batch ← loadBatch step
  let prediction ← model.forward batch
  let loss := objective prediction batch.targets
  let gradients ← backward loss
  parameters ← optimizer.step parameters gradients
```

The useful boundaries are already visible in the program: loading, forward evaluation, backward
evaluation, and the optimizer update. Start with those four names. A layer name, step number,
device, or tensor shape describes the circumstances of one call; it should not replace the name of
the work itself.

```
profileFromEnvironment "training" do
  for step in List.range steps do
    withStep step do
      let batch ← span "batch.load" (loadBatch step)
      let prediction ← span "model.forward" (model.forward batch)
      let loss := objective prediction batch.targets
      let gradients ← span "loss.backward" (backward loss)
      parameters ← span "optimizer.step" (optimizer.step parameters gradients)
```

This hierarchy remains readable in a ten-step experiment and a ten-thousand-step run. Repeated
calls share summary rows, while the trace still preserves every recorded step.

# Keep names stable and put variation in metadata
%%%
tag := "event-identity"
%%%

An event name answers “what work was this?” Metadata answers “under which conditions?” A stable
name makes runs comparable even when the module, shape, or backend changes.

```
span "model.forward" runAttention (metadata := {
  phase := some "forward"
  activity := some "operator"
  backend := some backendName
  dtype := some dtypeName
  device := some deviceName
  moduleName := some "encoder.block.0"
  graphNode := some nodeName
  stepIndex := some step
  inputShapes := #[inputShape]
  outputShapes := #[outputShape]
})
```

LeanProfiler uses the following fields as the summary key:

```
name, phase, activity, backend, dtype, device, module
```

Those fields split rows because they commonly identify meaningfully different implementations. A
CPU and CUDA forward pass should not be averaged together, and neither should two modules whose
costs need to be compared.

Step, graph node, and shape arrays remain attached to individual trace events. Putting a step
number in the grouping key would create one summary row per iteration. Putting arbitrary shapes in
the key could do the same for variable-length inputs. The trace is where those details belong; the
summary is where repeated observations become a distribution.

When another dimension really does define a separate benchmark population, use a stable name or
one of the grouping fields deliberately. Do not encode an entire JSON payload into an event name.

# Carry repeated context through the loop
%%%
tag := "metadata-context"
%%%

Most labels repeat across several nested spans. Dynamic context records them once:

```
for step in List.range steps do
  withStep step do
    span "batch.load" (loadBatch step) (metadata := {
      activity := some "data"
    })

    withModule "encoder.block.0" do
      withPhase "forward" do
        span "model.forward" (model.forward batch) (metadata := {
          backend := some backendName
          dtype := some dtypeName
          device := some deviceName
          inputShapes := #[inputShape]
          outputShapes := #[outputShape]
        })
```

`withStep`, `withModule`, and `withPhase` apply only while their actions run. Nesting them mirrors
the lexical structure of the measured program, so a later refactor does not depend on mutable
global labels.

An explicit scalar field on a span overrides the surrounding context. Shape arrays inherit from
the context only when the span supplies an empty array. This makes a broad module label convenient
without preventing one inner operation from naming a more precise module or shape.

# Keep one session around the question
%%%
tag := "session-ownership"
%%%

One `profile` call owns one capture buffer and produces one trace-summary pair. At the beginning of
the session it clears old events and enables recording. At the end it disables recording, checks
the event structure, computes summary rows, and writes both artifacts.

```
def profileTraining (config : ProfilerConfig) : IO Unit :=
  profile config "training" do
    runTrainingLoop
```

Nested `span` calls are normal. Nested or overlapping `profile` calls are rejected because two
sessions cannot safely own the same process-wide buffer or output paths.

The session also preserves the failure that matters. If `runTrainingLoop` throws, LeanProfiler
first attempts to export the completed spans and then rethrows the original exception. If export
fails as well, the export error is printed, but it does not hide the training failure. A partial
trace from a failed run is useful diagnostic evidence; it is not automatically a valid benchmark.

# Wait for worker tasks that belong to the run
%%%
tag := "worker-boundary"
%%%

A session ends when its top-level action returns. It cannot discover detached tasks or decide
whether they belong to the workload. Await every worker whose events should be present before
leaving the profiled action.

A worker thread has its own nesting stack. To retain the logical relationship with the caller,
capture the active parent index and install it in the worker:

```
let some parent ← currentSpanIndex
  | throw <| IO.userError "expected an active parent span"

let task ← IO.asTask do
  withParentIndex parent do
    span "worker.decode" decode

let _ ← task.get
```

The trace stores the worker's `parent_index`, so Perfetto can relate the decode operation to the
calling span. The analyzer does not subtract cross-thread children from a parent's self time.
Threads may overlap, and subtracting one thread's elapsed interval from another would turn a
causal link into a false exclusive-time calculation.

# Close a span only after asynchronous work finishes
%%%
tag := "completion-hooks"
%%%

An ordinary span stops when its host action returns. That is correct for synchronous work, but a
GPU launch or foreign runtime may return while the measured operation is still running.
`SpanHooks` makes the completion rule explicit:

```
prepare
  start timestamp
    action
    completeTiming
  stop timestamp
enrich
record event
```

`prepare` creates adapter state outside the timed interval. `completeTiming` waits for the work
whose completion defines the measurement. `enrich` runs after the stop timestamp and can attach
counters without adding their collection cost to the duration.

```
let hooks : SpanHooks := {
  State := DeviceToken
  prepare := makeTimingToken
  completeTiming := waitForDevice
  enrich := fun token metadata => do
    let live ← readLiveBytes token
    pure { metadata with allocLiveBytes := some live }
}

span "model.forward" forward
  (metadata := {
    device := some "cuda"
    timing := some "device-synchronized"
  })
  (hooks := hooks)
```

This span measures the host launch path, queue delay, required device work, and synchronization
overhead as one interval. It does not reveal individual kernels or memory copies. CUPTI, Kineto, or
a native device profiler is still needed for that lower-level timeline.

Errors from `completeTiming` and `enrich` are written to `metadata.hookError`. They do not replace
an exception raised by `forward`. An error from `prepare` occurs before the event is reserved and
returns directly to the caller.

# Keep long captures finite
%%%
tag := "event-limits"
%%%

A trace of every operation in a long training run can consume substantial memory and become harder
to inspect than the program itself. Set a retained-event limit when the workload is not naturally
small:

```
LEAN_PROFILE=1 \
LEAN_PROFILE_MAX_EVENTS=250000 \
lake exe your_executable
```

LeanProfiler retains the spans with the first 250,000 reserved indices. Later spans still run and
unwind their local nesting stacks, but their records are dropped. The summary reports both the
configured limit and `dropped_events`.

The retained prefix can still diagnose an early slowdown. It should not silently become a
performance baseline for the whole run. The comparison command rejects dropped events and
structural validation issues unless `--allow-incomplete` is supplied.

For repeated measurements, prefer a short scheduled capture after warmup rather than a very large
prefix. Scheduled captures also make baseline and candidate runs easier to compare.

# Give every memory number a precise meaning
%%%
tag := "allocation-semantics"
%%%

The metadata schema can carry allocated bytes, live bytes, peak bytes, and a net change, but the
core profiler does not manufacture those values. An allocator adapter must define which allocator
was observed, when it was sampled, and what each unit means.

Two snapshots can answer a narrow question:

```
net change = live bytes after - live bytes before
```

They cannot recover every allocation or the true peak if memory was allocated and freed between
the snapshots. A peak requires either a counter maintained by the allocator or an allocation event
stream. Process peak RSS is different again: it is a process-wide high-water mark, not live tensor
memory and not attribution to one span.

Record only the memory fields the adapter can justify. A missing field means “not measured.” It
should never be displayed or compared as zero.

# The resulting event tree
%%%
tag := "capture-result"
%%%

After these choices, one step of the training capture has a clear structure:

```
training
├── batch.load                 step=17, activity=data
├── model.forward              step=17, module=encoder.block.0
│                              backend=eager, device=cuda
├── loss.backward              step=17, phase=backward
└── optimizer.step             step=17, phase=optimizer
```

`withStep` supplies metadata; it does not create another span. The trace therefore keeps step 17 on
each event while preserving the actual parent relationships. The summary combines repeated steps
under stable keys. The synchronized forward interval states what completion means, and any memory
fields come from an identified adapter. Nothing in the report has to be interpreted as an
unlabelled convention.
