/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import NN.Tests.Runtime.Cuda.Suite

/-!
# TorchLean CUDA test executable

Runs TorchLean's focused CUDA kernel, autograd, numerical-parity, shape, ownership, and allocator
checks without first running unrelated dataset or Python interoperability suites.
-/

/--
Run the CUDA coverage suite selected by the current TorchLean native build.

The allocator cache-cap test re-executes this binary with a fixed native environment. Its child
must run only the cache probe; entering the full suite again would recursively fork more children.
-/
public def main : IO Unit := do
  match ← IO.getEnv "TORCHLEAN_CUDA_CACHE_PROBE" with
  | some "cache-cap" => Tests.Cuda.Stress.runCacheCapProbe
  | _ => Tests.Cuda.run
