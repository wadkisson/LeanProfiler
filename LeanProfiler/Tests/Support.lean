/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

import Std

/-!
# Test support

Small assertions shared by the executable test modules.
-/

namespace LeanProfiler.Tests

/-- Fail a test with its suite and assertion labels. -/
public def expect (suite label : String) (condition : Bool) : IO Unit := do
  unless condition do
    throw <| IO.userError s!"{suite} test failed: {label}"

end LeanProfiler.Tests
