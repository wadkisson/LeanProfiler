/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
Authors: LeanProfiler Team
-/

module

public import LeanProfiler.CLI.Compare

/-!
# Command routing

Help text and routing for the standalone comparison command.
-/

namespace LeanProfiler.CLI

/-- Help text for the standalone comparison command. -/
public def usage : String :=
  "Usage:\n"
  ++ "  leanprofiler compare BASELINE CANDIDATE [options]\n\n"
  ++ "Options:\n"
  ++ "  --metric METRIC                    Comparison metric (default: mean_ns)\n"
  ++ "  --absolute-tolerance N             Allowed increase in the metric's native unit\n"
  ++ "  --relative-tolerance-bps N         Allowed relative increase in basis points\n"
  ++ "  --json PATH                        Write the detailed comparison as JSON\n"
  ++ "  --fail-on-new                      Fail when the candidate adds a summary key\n"
  ++ "  --fail-on-missing                  Fail when a baseline summary key is absent\n"
  ++ "  --allow-incomplete                 Accept dropped events or validation issues\n"
  ++ "  -h, --help                         Show this help\n\n"
  ++ "An increase is a regression only when it exceeds both tolerances."

def runCompareCommand (args : List String) : IO UInt32 :=
  match parseCompareOptions args with
  | .error message => do
      IO.eprintln s!"leanprofiler compare: {message}"
      IO.eprintln usage
      pure 2
  | .ok options =>
      try
        compareArtifacts options
      catch error =>
        IO.eprintln s!"leanprofiler compare: {error}"
        pure 2

/--
Handle a LeanProfiler command. `none` leaves the arguments available to an enclosing application's
command router.
-/
public def route : List String → IO (Option UInt32)
  | "--" :: "compare" :: args =>
      route ("compare" :: args)
  | "compare" :: "--help" :: [] => do
      IO.println usage
      pure (some 0)
  | "compare" :: "-h" :: [] => do
      IO.println usage
      pure (some 0)
  | "compare" :: args =>
      some <$> runCompareCommand args
  | _ => pure none

end LeanProfiler.CLI
