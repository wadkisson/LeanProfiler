/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

import VersoManual
import LeanProfiler
import LeanProfiler.Proofs

open Verso.Genre Manual

#doc (Manual) "Read the trace and summary" =>
%%%
tag := "results"
%%%

The nested example recorded seven events on one Lean thread. Its trace preserves the order of the
run: each source read is followed by one analysis pass, all under one root event. This timeline is
generated from the checked-in Trace Event file:

![A nested timeline with one root span and alternating source.read and source.analyze child spans](../../Assets/nested-spans-timeline.svg)

The capture came from one real run on Linux with Lean 4.32.0. Its names, nesting, and metadata come
from the program. Its durations are observations, not reference performance.

Download
[the same trace](../../Assets/nested-spans-trace.json) and open it in
[Perfetto](https://ui.perfetto.dev) to inspect event arguments and zoom the timeline.

The summary collapses the repeated calls into three rows. The same run printed this table before
writing its two files:

```
Lean profile: 7 events, 1 threads, window 18.55 ms,
recorded thread time 18.55 ms, 287 Lean heartbeats
Process resources: user CPU 0 ms, system CPU 0 ms, peak RSS 150712 KiB, context switches 6

Name                                      Self       Total  Calls      Mean       P95  Self HB      %
source.analyze [phase=analysis, module…  12.22 ms   12.22 ms      3   4.07 ms   4.08 ms        6  65.8%
source.read [phase=read, activity=files…  6.21 ms    6.21 ms      3   2.07 ms   2.08 ms        6  33.4%
example.source-indexer                   114.82 us   18.55 ms      1  18.55 ms  18.55 ms      275   0.6%

Trace: build/leanprofiler-trace.json
Summary: build/leanprofiler-summary.json
```

The analysis calls account for about two thirds of recorded thread time and the reads account for
about one third. The enclosing root spans the full run, but almost all of that interval belongs to
its children:

![Inclusive and self time for the three grouped rows in the nested example](../../Assets/time-breakdown.svg)

The root is slow because its children are slow, not because of work performed directly in the root.
Exact durations move between machines and runs. Event names, grouping fields, call counts, and the
relationship between self and total time should remain stable for an unchanged workload.

# Total and self time
%%%
tag := "total-and-self-time"
%%%

For an event `e`, total time is its nonnegative interval length:

$$`\operatorname{total}(e)=\max(0,\operatorname{end}(e)-\operatorname{start}(e))`

Self time subtracts the covered union of immediate same-thread child intervals:

$$`\operatorname{self}(e)
=\operatorname{total}(e)
-\min(\operatorname{total}(e),\operatorname{coveredChildren}(e))`

The union prevents overlapping malformed children from being counted twice. Child intervals are
clipped to the parent before diagnostic subtraction. The validator still reports the malformed
relationship.

A grandchild lies inside an immediate child in a valid nesting tree, so subtracting immediate
children is enough. Cross-thread logical children remain linked but are not subtracted.

LeanProfiler proves the inclusive bounds used by this calculation:

```
#check LeanProfiler.EventTiming.selfNs_le_inclusiveNs
#check LeanProfiler.EventTiming.selfHeartbeats_le_inclusiveHeartbeats
#check LeanProfiler.analyze_timings_areConsistent
```

These theorems describe the analyzer. They do not prove that the clock has a particular physical
resolution or that the profiled action implements its intended algorithm.

# Capture totals
%%%
tag := "capture-totals"
%%%

`trace_window_ns` runs from the earliest retained start to the latest retained end.

`recorded_thread_time_ns` is the sum of every event's self time. Parallel threads can make this
larger than the trace window. It is not CPU utilization.

`recorded_heartbeats` is the matching sum of self heartbeats. Each row's `share_permille` is:

$$`1000\cdot
\frac{\text{row self time}}{\text{recorded thread time}}`

The implementation uses integer division, so displayed percentages can lose a tenth of a percent
and need not sum to exactly 100%.

# Grouped rows
%%%
tag := "grouped-rows"
%%%

Rows use this key:

```
name, phase, activity, backend, dtype, device, module
```

For each key, the summary stores:

- call count;
- total and self-time sums;
- minimum, mean, median, nearest-rank p95, and maximum total duration;
- total and self heartbeats;
- supplied allocation totals and peak live bytes.

Total time can double-count nested work. Rank by self time when asking where recorded host time
went. Use total time when asking how long callers waited for a named region.

The saved summary contains this real row:

```
{
  "key": {
    "name": "source.analyze",
    "phase": "analysis",
    "activity": null,
    "backend": null,
    "dtype": null,
    "device": null,
    "module": "indexer"
  },
  "calls": 3,
  "self_ns": 12223861,
  "total_ns": 12223861,
  "mean_ns": 4074620,
  "p95_ns": 4081433,
  "share_permille": 658
}
```

The three analysis calls lasted about four milliseconds each because this example sleeps for four
milliseconds. Scheduler and timer behavior account for the extra time.

The [complete summary](../../Assets/nested-spans-summary.json) includes all required version-1
fields.

# Heartbeats
%%%
tag := "heartbeats"
%%%

Lean heartbeats count work mainly through small allocations on the current execution thread, with
extra weight for selected allocation-avoiding paths. They are useful beside elapsed time when
managed Lean work stays similar but wall-clock noise moves.

Heartbeats are not instructions, cycles, bytes, or device work. A foreign call can take a long time
while adding few Lean heartbeats. Each Lean thread has its own counter.

# Process counters
%%%
tag := "process-counters"
%%%

The session samples `Std.IO.Process.getResourceUsage` at its boundaries. The summary reports
changes in:

- user and system CPU time in integer milliseconds;
- minor and major page faults;
- block input and output operations;
- voluntary and involuntary context switches.

It also reports ending peak resident set size and any increase during the capture. Peak RSS is a
high-water mark, not current live memory. These counters cover the whole process, including
unprofiled threads and foreign code, so they do not belong to an individual row.

# Structural validation
%%%
tag := "structural-validation"
%%%

`analyze` checks:

- reversed intervals;
- duplicate indices;
- missing or non-earlier parents;
- incorrect root or child depths;
- same-thread children outside their parent interval;
- overlapping immediate siblings on one thread.

Analysis continues after a problem so the trace remains inspectable. A report with issues is
diagnostic data. The strict summary reader rejects missing fields, unknown fields, non-integer
nanoseconds, duplicate keys, inconsistent totals, and malformed retained-index prefixes.

# Trace Event units
%%%
tag := "trace-event-units"
%%%

The summary stores integer nanoseconds and declares a monotonic clock. The
[Trace Event format](https://perfetto.dev/docs/getting-started/other-formats) uses microseconds, so
the exporter writes fractional microseconds:

```
1234 ns  →  "ts": 1.234
4567 ns  →  "dur": 4.567
```

The event arguments retain the original integer `start_ns` and `duration_ns`. `displayTimeUnit:
"ns"` asks a viewer to show fine-grained values; it does not change Trace Event's required units.
