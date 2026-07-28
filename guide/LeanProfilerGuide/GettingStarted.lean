/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

import VersoManual
import LeanProfiler

open Verso.Genre Manual

#doc (Manual) "Record your first run" =>
%%%
tag := "getting-started"
%%%

Start with the few boundaries you would name while explaining the program to another person. For a
training step, those may be loading, forward evaluation, backward evaluation, and the optimizer.
For a server request, they may be parsing, lookup, computation, and serialization. A handful of
broad spans is easier to read than hundreds of tiny events, and it usually makes the next question
obvious.

Add LeanProfiler to the Lake package that owns the executable:

```
[[require]]
name = "LeanProfiler"
git = "https://github.com/lean-dojo/LeanProfiler"
rev = "main"
```

Import the package and put one session around the run. Spans can then name the phases inside it:

```
import LeanProfiler

open LeanProfiler

def loadBatch : IO Unit :=
  IO.sleep 2

def runForward : IO Unit :=
  IO.sleep 4

def main : IO Unit :=
  profileFromEnvironment "training.step" do
    span "input.load" loadBatch
    span "model.forward" runForward (metadata := {
      phase := some "forward"
      backend := some "eager"
      dtype := some "float32"
      device := some "cpu"
      inputShapes := #["32×784"]
    })
```

Run the executable with profiling enabled:

```
LEAN_PROFILE=1 lake exe your_executable
```

The default files are:

```
build/leanprofiler-trace.json
build/leanprofiler-summary.json
```

The trace records every completed span in Trace Event format. Open it in
[Perfetto](https://ui.perfetto.dev) to zoom through the run and inspect metadata. The summary groups
repeated spans and keeps integer-nanosecond measurements, Lean heartbeats, validation issues, and
session resource counters.

Without `LEAN_PROFILE=1`, `profileFromEnvironment` still runs the action. It does not retain spans
or write reports. Instrumentation can therefore remain in normal application code. Enabled spans
still have measurement overhead, so capture only the interval and detail needed for the question.

The session above produces a root event with two children:

```
training.step
├── input.load
└── model.forward
```

That small hierarchy already distinguishes a slow loader from a slow model call. Nest narrower
spans only after the first trace points to one of them.

# Use an explicit configuration
%%%
tag := "explicit-configuration"
%%%

Environment variables are convenient for commands and CI. A library or long-running application
can pass the same settings directly:

```
def runProfiled (config : ProfilerConfig) : IO Unit :=
  profile config "worker" do
    span "work" runWork
```

The main configuration fields are:

:::table +header
*
  * Field
  * Meaning
*
  * `enabled`
  * record spans and export reports
*
  * `tracePath`
  * Trace Event JSON destination
*
  * `summaryPath`
  * strict summary JSON destination
*
  * `eventLimit`
  * maximum retained span count, or no limit
*
  * `processName`
  * process-track label shown by Perfetto
:::

The environment entry point reads these variables:

:::table +header
*
  * Variable
  * Setting
*
  * `LEAN_PROFILE`
  * enable the session unless set to an empty or false-like value
*
  * `LEAN_PROFILE_OUT`
  * trace path
*
  * `LEAN_PROFILE_SUMMARY_OUT`
  * summary path
*
  * `LEAN_PROFILE_MAX_EVENTS`
  * retained event limit
*
  * `LEAN_PROFILE_PROCESS_NAME`
  * Perfetto process label
:::

Keep explicit paths when saving several runs:

```
LEAN_PROFILE=1 \
LEAN_PROFILE_OUT=build/traces/baseline.json \
LEAN_PROFILE_SUMMARY_OUT=build/summaries/baseline.json \
LEAN_PROFILE_PROCESS_NAME="baseline worker" \
lake exe your_executable
```

# Run the checked-in example
%%%
tag := "checked-in-example"
%%%

Run the checked-in version of this experiment from the repository root:

```
LEAN_PROFILE=1 lake exe leanprofiler_nested_example
```

It records this pair three times:

```
example.nested-spans
├── input.load
└── model.forward
```

The load span carries an input phase and activity. The forward span carries a forward phase and
module name. Step numbers remain on individual trace events, while the three repeated calls share
one summary row. This distinction is important: the timeline preserves each observation, while the
summary provides the distribution used for comparisons.

The other examples cover two boundaries that are easy to miss:

```
LEAN_PROFILE=1 lake exe leanprofiler_async_example
LEAN_PROFILE=1 lake exe leanprofiler_schedule_example
```

`AsyncCompletion` waits for a task through a completion hook before taking the stop timestamp.
`ScheduledSteps` runs skipped and warmup work before opening the recorded interval. Reach for these
examples after a first capture points to asynchronous completion or startup effects.

# Time work, not a lazy value
%%%
tag := "io-timing-boundary"
%%%

`span` accepts an `IO` action. That boundary matters because a pure value can remain partly
unevaluated until a later action prints, stores, or passes it to foreign code. Put the span around
the action that actually forces the work.

The optional `profiled def` syntax keeps a small `IO` function concise. It has its own import
because defining a command requires Lean's compiler front end:

```
import LeanProfiler.Syntax

open LeanProfiler

profiled def loadBatch : IO Unit := do
  IO.sleep 2
```

Use an explicit `span` when the same function needs different names or metadata at different call
sites.
