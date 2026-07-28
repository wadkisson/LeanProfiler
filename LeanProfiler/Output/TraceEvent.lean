/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Analysis.Report
public import LeanProfiler.Config
public import Lean.Data.Json
import LeanProfiler.Internal.Json
import LeanProfiler.Runtime.Capture
import Std.Data.HashSet

/-!
# Trace Event JSON

The exported trace opens in Perfetto and Chrome tracing. Timestamps use microseconds as required by
the Trace Event format, while three decimal places preserve the recorded nanoseconds.
-/

namespace LeanProfiler
namespace Internal

/--
Encode nanoseconds as a Trace Event microsecond number without dropping sub-microsecond digits.
`1234 ns` becomes the JSON number `1.234`.
-/
def traceMicros (ns : Nat) : Lean.Json :=
  .num { mantissa := Int.ofNat ns, exponent := 3 }

def stringArrayJson (values : Array String) : Lean.Json :=
  .arr (values.map Lean.Json.str)

def metadataJson (metadata : Metadata) : Lean.Json :=
  Lean.Json.mkObj [
    ("phase", Internal.Json.option Lean.Json.str metadata.phase),
    ("activity", Internal.Json.option Lean.Json.str metadata.activity),
    ("backend", Internal.Json.option Lean.Json.str metadata.backend),
    ("dtype", Internal.Json.option Lean.Json.str metadata.dtype),
    ("device", Internal.Json.option Lean.Json.str metadata.device),
    ("timing", Internal.Json.option Lean.Json.str metadata.timing),
    ("module", Internal.Json.option Lean.Json.str metadata.moduleName),
    ("graph_node", Internal.Json.option Lean.Json.str metadata.graphNode),
    ("step", Internal.Json.option Internal.Json.nat metadata.stepIndex),
    ("input_shapes", stringArrayJson metadata.inputShapes),
    ("output_shapes", stringArrayJson metadata.outputShapes),
    ("alloc_bytes", Internal.Json.option Internal.Json.nat metadata.allocBytes),
    ("alloc_live_bytes", Internal.Json.option Internal.Json.nat metadata.allocLiveBytes),
    ("alloc_peak_bytes", Internal.Json.option Internal.Json.nat metadata.allocPeakBytes),
    ("alloc_delta_bytes", Internal.Json.option Internal.Json.int metadata.allocDeltaBytes),
    ("hook_error", Internal.Json.option Lean.Json.str metadata.hookError)
  ]

def traceCategory (event : Event) : String :=
  String.intercalate "," <|
    ["lean"] ++ [event.metadata.phase, event.metadata.activity].filterMap id

def eventJson (originNs : Nat) (event : Event) : Lean.Json :=
  Lean.Json.mkObj [
    ("name", .str event.name),
    ("cat", .str (traceCategory event)),
    ("ph", .str "X"),
    ("ts", traceMicros (event.startNs - originNs)),
    ("dur", traceMicros event.durationNs),
    ("pid", Internal.Json.nat currentProcessId.toNat),
    ("tid", Internal.Json.nat event.threadId.toNat),
    ("args", Lean.Json.mkObj [
      ("event_index", Internal.Json.nat event.index),
      ("parent_index", Internal.Json.option Internal.Json.nat event.parentIndex),
      ("depth", Internal.Json.nat event.depth),
      ("start_ns", Internal.Json.nat event.startNs),
      ("duration_ns", Internal.Json.nat event.durationNs),
      ("heartbeats", Internal.Json.nat event.heartbeats),
      ("metadata", metadataJson event.metadata)
    ])
  ]

def processNameEventJson (processName : String) : Lean.Json :=
  Lean.Json.mkObj [
    ("name", .str "process_name"),
    ("ph", .str "M"),
    ("pid", Internal.Json.nat currentProcessId.toNat),
    ("tid", Internal.Json.nat 0),
    ("args", Lean.Json.mkObj [("name", .str processName)])
  ]

def threadNameEventJson (threadId : UInt64) : Lean.Json :=
  Lean.Json.mkObj [
    ("name", .str "thread_name"),
    ("ph", .str "M"),
    ("pid", Internal.Json.nat currentProcessId.toNat),
    ("tid", Internal.Json.nat threadId.toNat),
    ("args", Lean.Json.mkObj [("name", .str s!"Lean thread {threadId}")])
  ]

end Internal

/--
Trace Event JSON accepted by Chrome tracing and Perfetto.

The optional process name labels the process track without changing event grouping.
-/
public def traceJson (report : Report)
    (processName : String := ProfilerConfig.defaults.processName) : Lean.Json :=
  let threadIds :=
    (report.events.foldl (init := ({} : Std.HashSet UInt64))
      fun ids event => ids.insert event.threadId).toArray.qsort (· < ·)
  let metadataEvents :=
    #[Internal.processNameEventJson processName] ++ threadIds.map Internal.threadNameEventJson
  Lean.Json.mkObj [
    ("displayTimeUnit", .str "ns"),
    ("traceEvents", .arr <|
      metadataEvents ++ report.events.map (Internal.eventJson report.traceOriginNs))
  ]

end LeanProfiler
