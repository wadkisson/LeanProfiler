/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import Examples.NestedWorkload

/-!
# Nested spans

Records a short workload with step, module, and phase metadata. Run it with
`LEAN_PROFILE=1 lake exe leanprofiler_nested_example`.
-/

/-- Run the nested-span example with the environment configuration. -/
public def main : IO Unit :=
  LeanProfiler.Examples.NestedWorkload.run LeanProfiler.startupConfig
