/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Analysis.Report
public import Lean.Data.Json

/-!
# JSON building blocks

Small encoders shared by report and comparison artifacts.
-/

namespace LeanProfiler.Internal.Json

/-- Encode a natural number without passing through floating point. -/
public def nat (value : Nat) : Lean.Json :=
  .num (Lean.JsonNumber.fromNat value)

/-- Encode a signed integer without passing through floating point. -/
public def int (value : Int) : Lean.Json :=
  .num (Lean.JsonNumber.fromInt value)

/-- Encode an optional value as either its JSON representation or `null`. -/
public def option (encode : α → Lean.Json) : Option α → Lean.Json
  | none => .null
  | some value => encode value

/-- Encode the complete key used to group and compare profiler rows. -/
public def summaryKey (key : SummaryKey) : Lean.Json :=
  Lean.Json.mkObj [
    ("name", .str key.name),
    ("phase", option Lean.Json.str key.phase),
    ("activity", option Lean.Json.str key.activity),
    ("backend", option Lean.Json.str key.backend),
    ("dtype", option Lean.Json.str key.dtype),
    ("device", option Lean.Json.str key.device),
    ("module", option Lean.Json.str key.moduleName)
  ]

end LeanProfiler.Internal.Json
