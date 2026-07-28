/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

import VersoManual
import LeanProfiler
import LeanProfiler.Proofs

open Verso.Genre Manual

#doc (Manual) "Compare two runs" =>
%%%
tag := "regressions"
%%%

Now change exactly one part of the running example. The baseline spends about four milliseconds in
each `source.analyze` span; the candidate spends ten. Both captures retain three files and keep the
two-millisecond read delay unchanged.

Generate both captures and their comparison:

```
lake exe leanprofiler_regression_example
```

The executable writes its artifacts under `build/regression-walkthrough`. To compare existing
summaries directly, use the command-line interface:

```
lake exe leanprofiler compare \
  build/regression-walkthrough/baseline-summary.json \
  build/regression-walkthrough/candidate-summary.json \
  --metric p95_ns \
  --absolute-tolerance 500000 \
  --relative-tolerance-bps 1000 \
  --json build/regression-walkthrough/comparison.json
```

The candidate crosses both allowances for `source.analyze` and for the enclosing root span. The
read row stays effectively unchanged, which is the evidence that localizes the regression:

![A paired-dot plot comparing baseline and candidate p95 values for the three nested example rows](../../Assets/p95-comparison.svg)

The root regression is a consequence of the forward regression; it is not a second independent
cause. The checked-in inputs behind the figure are available as
[baseline summary](../../Assets/nested-spans-summary.json),
[candidate summary](../../Assets/comparison-candidate-summary.json), and
[comparison JSON](../../Assets/comparison.json).

# Schedule a capture
%%%
tag := "capture-schedule"
%%%

Long loops rarely need a trace of every step. Startup and compilation can also dominate the first
iterations. `Schedule.create` classifies zero-based steps into skip, warmup, record, and
record-and-save phases:

```
let .ok schedule := Schedule.create
    (skipFirst := 2)
    (wait := 1)
    (warmup := 2)
    (active := 3)
    (repeatCount := 2)
  | throw <| IO.userError "active must be positive"
```

The example schedule creates two short active captures inside one longer run:

![Two repeated capture cycles with skipped, warmup, recorded, and save steps](../../Assets/capture-schedule.svg)

After the initial skip, each cycle is:

```
wait → warmup → active
```

The last active step returns `recordAndSave`. With `active = 1`, that only active step records and
saves. A zero repeat count continues cycling; a positive repeat count eventually returns `skip`
for every later step.

`Schedule.actionAt` only classifies. The loop may own capture state itself:

```
let action := schedule.actionAt step
if action.records then
  recordStep step
else
  runStep step
if action.saves then
  saveCycle
```

`runScheduledCycle` runs one complete cycle and opens the session around the active interval:

```
let ran ← runScheduledCycle schedule cycle config captureName fun step action =>
  runStep step action
```

Skipped, waiting, and warmup callbacks run before capture begins. They can still change application
state, so the active interval begins from the same state the unprofiled loop would have reached.
Give every retained cycle its own trace and summary paths.

The schedule lemmas establish its boundary behavior:

```
#check LeanProfiler.Schedule.cycleLength_pos
#check LeanProfiler.Schedule.actionAt_eq_skip_of_lt_skipFirst
#check LeanProfiler.ProfilerAction.records_of_saves
```

# Pick the metric that matches the question
%%%
tag := "comparison-metrics"
%%%

Available metrics are:

```
total_ns             self_ns
mean_ns              median_ns
p95_ns               max_ns
total_heartbeats     self_heartbeats
alloc_bytes          peak_live_bytes
```

Use mean, median, or p95 for per-call latency when the call count still represents the same
workload. Use total or self time when the amount of recorded work is itself the target.

Heartbeat metrics focus on Lean-managed work. Allocation metrics are meaningful only when both
captures use hooks with the same allocator semantics.

# Set both tolerances
%%%
tag := "comparison-tolerances"
%%%

A comparison threshold has an absolute allowance in the metric's native unit and a relative
allowance in basis points:

```
let config : ComparisonConfig := {
  metric := .p95Ns
  threshold := {
    absolute := 500_000
    relativeBps := 1000
  }
}
```

For a nanosecond metric, this allows 0.5 milliseconds and 10%. An increase is a regression only
when it is strictly greater than both. This keeps a high percentage on a tiny span below the
absolute noise floor, while a small absolute change on a long span stays below the relative
allowance.

When the baseline is zero, only the absolute allowance can be evaluated.

# Match the whole key
%%%
tag := "comparison-keys"
%%%

Comparisons match name, phase, activity, backend, dtype, device, and module. A row found only in the
baseline is `missing`; one found only in the candidate is `new`.

Those categories are reported without failing by default because instrumentation can change
deliberately. Use `--fail-on-new` or `--fail-on-missing` when the key set is part of the benchmark
contract.

The result stores the baseline and candidate values, signed delta, basis-point change, call counts,
and one of:

- `improvement`;
- `within_tolerance`;
- `regression`.

# Treat summaries as inputs, not loose JSON
%%%
tag := "strict-summary-input"
%%%

The command returns:

:::table +header
*
  * Exit
  * Meaning
*
  * `0`
  * selected policy passed
*
  * `1`
  * a regression or requested key policy failed
*
  * `2`
  * arguments or artifacts were invalid
:::

It refuses summaries with dropped events or analyzer issues. `--allow-incomplete` is available for
deliberate diagnosis and is recorded in the comparison JSON.

# Collect defensible samples
%%%
tag := "repeatable-measurement"
%%%

A p95 inside one report describes calls in that process. It is not a confidence interval over
independent runs. For a change that matters:

1. pin the Lean toolchain and Lake manifests;
2. use the same build settings and machine;
3. fix workload, seed, backend, dtype, device, and synchronization policy;
4. isolate warmup from active samples;
5. collect several independent baseline and candidate runs;
6. inspect the distribution before setting a tolerance;
7. retain traces and summaries for failed comparisons.

Never share a baseline between an unsynchronized GPU launch span and a synchronized completion
span. They measure different intervals.
