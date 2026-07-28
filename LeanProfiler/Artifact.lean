/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Output
public import LeanProfiler.Artifact.Summary
public import LeanProfiler.Artifact.Decode
public import LeanProfiler.Artifact.Validation
public import LeanProfiler.Artifact.Read

/-!
# Summary artifacts

Version 1 decoding rejects missing data, numeric coercions, unknown fields, and inconsistent totals
with field-specific errors.
-/
