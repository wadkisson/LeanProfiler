/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.Instrumentation
import Lean

/-!
# Instrumentation command

Import this module when using `profiled def`. Function-based instrumentation through `span`,
`profile`, and `profileFromEnvironment` is available from the lighter `LeanProfiler` import.
-/

namespace LeanProfiler

open Lean

/--
Define an `IO` function with a span named after the declaration.

The generated definition must return `IO`; inferred and aliased `IO` result types work without
syntax inspection. Pure declarations are rejected. Use an ordinary `def` and place `span` around
the `IO` boundary that forces the pure computation.
-/
macro modifiers:declModifiers "profiled " "def " id:declId signature:optDeclSig
    " := " body:term : command => do
  let declarationName := id.raw[0].getId
  let spanName := Syntax.mkStrLit declarationName.toString
  if declarationName == `main then
    `($modifiers:declModifiers def $id:declId $signature:optDeclSig :=
        LeanProfiler.Internal.runSession LeanProfiler.startupConfig $spanName (fun _ => $body))
  else
    `($modifiers:declModifiers def $id:declId $signature:optDeclSig :=
        LeanProfiler.Internal.spanThunk $spanName (fun _ => $body))

end LeanProfiler
