/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Runtime.Span
public import NN.Runtime.Autograd.Engine.Cuda.Buffer

/-!
# TorchLean CUDA profiling

The adapter makes a host span wait for the current CUDA device and adds TorchLean allocator
snapshots. It remains outside the core profiler so importing `LeanProfiler` does not require CUDA.
-/

namespace LeanProfiler.TorchLean.Cuda

open Runtime.Autograd.Cuda

@[extern "leanprofiler_torchlean_cuda_synchronize"]
opaque synchronizeRaw (token : UInt64) : UInt32

/--
Wait until work already submitted to the current CUDA device has completed.

The returned CUDA status is checked in Lean so a failed fence is retained as a hook diagnostic.
-/
public def synchronize : IO Unit := do
  let token ← IO.monoNanosNow
  let status := synchronizeRaw (UInt64.ofNat token)
  unless status == 0 do
    throw <| IO.userError s!"CUDA synchronization failed with status {status}"

/-- Signed difference between two monotonically sampled unsigned byte counters. -/
def byteDelta (before after : UInt64) : Int :=
  if before ≤ after then
    Int.ofNat (after - before).toNat
  else
    -Int.ofNat (before - after).toNat

/--
Synchronize CUDA at the end of a span and attach TorchLean allocator counters.

The recorded host duration includes outstanding queue time and the synchronization itself.
`allocLiveBytes`, `allocPeakBytes`, and `allocDeltaBytes` describe TorchLean-owned device buffers,
not allocations made by unrelated CUDA libraries.
-/
public def spanHooks : SpanHooks where
  State := Buffer.AllocatorStats
  prepare := do
    Buffer.requireNativeRuntime
    Buffer.allocatorStats
  completeTiming := fun _ => synchronize
  enrich := fun before metadata => do
    let after ← Buffer.allocatorStats
    pure {
      metadata with
      device := some "cuda"
      timing := some "device-synchronized"
      allocLiveBytes := some after.liveBytes.toNat
      allocPeakBytes := some after.peakBytes.toNat
      allocDeltaBytes := some (byteDelta before.liveBytes after.liveBytes)
    }

end LeanProfiler.TorchLean.Cuda
