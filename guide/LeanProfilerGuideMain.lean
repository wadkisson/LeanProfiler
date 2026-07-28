/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

import VersoManual
import LeanProfilerGuide.Manual

open Verso Doc
open Verso.Genre Manual

open Verso Output Html in
private def guideStyles : Html :=
  {{ <link rel="stylesheet" href="Assets/guide.css"/> }}

private def guideConfig : RenderConfig where
  -- Verso copies the checked-in captures and Lean-generated figures beside the rendered pages.
  extraFiles := [("LeanProfilerGuide/Assets", "Assets")]
  extraHead := #[guideStyles]

/-- Render the LeanProfiler manual with its checked-in artifacts. -/
def main (args : List String) : IO UInt32 :=
  manualMain
    (%doc LeanProfilerGuide.Manual)
    args
    (config := guideConfig)
    (extensionImpls := by exact extension_impls%)
