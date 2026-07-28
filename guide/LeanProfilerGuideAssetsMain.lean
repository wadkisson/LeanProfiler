/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

import LeanProfilerGuide.AssetRenderer

/-- Command-line synopsis for deterministic guide asset generation. -/
def usage : String :=
  "Usage: leanprofiler-guide-assets [ASSET_DIRECTORY]"

/-- Regenerate the guide figures in `directory`, reporting a command-style exit code. -/
def renderAssets (directory : System.FilePath) : IO UInt32 := do
  try
    LeanProfilerGuide.AssetRenderer.render directory
    pure 0
  catch error =>
    IO.eprintln s!"leanprofiler-guide-assets: {error}"
    pure 1

/-- Regenerate the checked-in figures, optionally using an explicit asset directory. -/
def main (args : List String) : IO UInt32 :=
  match args with
  | [] => renderAssets "LeanProfilerGuide/Assets"
  | [path] => renderAssets (System.FilePath.mk path)
  | _ => do
      IO.eprintln usage
      pure 2
