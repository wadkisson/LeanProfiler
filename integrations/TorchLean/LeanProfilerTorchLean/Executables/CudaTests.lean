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

/-- Run the CUDA coverage suite selected by the current TorchLean native build. -/
public def main : IO Unit :=
  Tests.Cuda.run
