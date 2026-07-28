/*
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
*/

#include <stdint.h>

/*
Return a nonzero status in portable builds.

The Lean adapter checks TorchLean's runtime status before calling this function, so reaching the
stub indicates a mismatched native configuration rather than a successful synchronization.
*/
uint32_t leanprofiler_torchlean_cuda_synchronize(uint64_t token) {
  (void)token;
  return 1;
}
