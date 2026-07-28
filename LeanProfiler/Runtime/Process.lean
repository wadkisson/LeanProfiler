/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Runtime.Event
import Std.Async.Process

/-!
# Process measurements

LeanProfiler samples operating-system resource counters at the start and end of a capture. These
measure the whole process, including worker threads and foreign code.
-/

namespace LeanProfiler

/--
Whole-process resource changes during a capture.

CPU values have the integer-millisecond resolution supplied by `getrusage`. They include every
thread in the process. Peak RSS is a process high-water mark; `peakResidentSetIncreaseKb` reports
how much that high-water mark rose during the capture.
-/
public structure ProcessMetrics where
  userCpuMs : Nat
  systemCpuMs : Nat
  peakResidentSetSizeKb : Nat
  peakResidentSetIncreaseKb : Nat
  minorPageFaults : Nat
  majorPageFaults : Nat
  blockInputOps : Nat
  blockOutputOps : Nat
  voluntaryContextSwitches : Nat
  involuntaryContextSwitches : Nat
  deriving Repr, Inhabited, DecidableEq

namespace Internal

/--
Cumulative operating-system counters captured at one instant.

Two snapshots form the endpoints used to calculate the `ProcessMetrics` for one capture.
-/
public structure ProcessSnapshot where
  userCpuMs : Nat
  systemCpuMs : Nat
  peakResidentSetSizeKb : Nat
  minorPageFaults : Nat
  majorPageFaults : Nat
  blockInputOps : Nat
  blockOutputOps : Nat
  voluntaryContextSwitches : Nat
  involuntaryContextSwitches : Nat
  deriving Repr, Inhabited, DecidableEq

/--
Read a cumulative process snapshot.

The standard library has already converted CPU time to whole milliseconds. The remaining values
are monotone counters, except peak RSS, which is the process high-water mark.
-/
public def sampleProcess : IO ProcessSnapshot := do
  let usage ← Std.IO.Process.getResourceUsage
  pure {
    userCpuMs := usage.cpuUserTime.val.toNat
    systemCpuMs := usage.cpuSystemTime.val.toNat
    peakResidentSetSizeKb := usage.peakResidentSetSizeKb.toNat
    minorPageFaults := usage.minorPageFaults.toNat
    majorPageFaults := usage.majorPageFaults.toNat
    blockInputOps := usage.blockInputOps.toNat
    blockOutputOps := usage.blockOutputOps.toNat
    voluntaryContextSwitches := usage.voluntaryContextSwitches.toNat
    involuntaryContextSwitches := usage.involuntaryContextSwitches.toNat
  }

/--
Subtract two process snapshots.

Natural-number subtraction deliberately saturates at zero if the operating system resets a
counter. Peak RSS remains the ending high-water mark, with its increase reported separately.
-/
public def processDelta (finish start : ProcessSnapshot) : ProcessMetrics :=
  {
    userCpuMs := finish.userCpuMs - start.userCpuMs
    systemCpuMs := finish.systemCpuMs - start.systemCpuMs
    peakResidentSetSizeKb := finish.peakResidentSetSizeKb
    peakResidentSetIncreaseKb :=
      finish.peakResidentSetSizeKb - start.peakResidentSetSizeKb
    minorPageFaults := finish.minorPageFaults - start.minorPageFaults
    majorPageFaults := finish.majorPageFaults - start.majorPageFaults
    blockInputOps := finish.blockInputOps - start.blockInputOps
    blockOutputOps := finish.blockOutputOps - start.blockOutputOps
    voluntaryContextSwitches :=
      finish.voluntaryContextSwitches - start.voluntaryContextSwitches
    involuntaryContextSwitches :=
      finish.involuntaryContextSwitches - start.involuntaryContextSwitches
  }

end Internal
end LeanProfiler
