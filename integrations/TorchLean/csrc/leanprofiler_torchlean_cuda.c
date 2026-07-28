/*
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
*/

#include <stdint.h>
#include <cuda_runtime_api.h>

/*
Synchronize the current CUDA device and return CUDA's status code.

The changing token comes from Lean's IO sequence. It prevents the compiler from treating two
otherwise identical synchronization calls as the same pure external expression.
*/
uint32_t leanprofiler_torchlean_cuda_synchronize(uint64_t token) {
  (void)token;
  return (uint32_t)cudaDeviceSynchronize();
}
