module

public import Lean

@[expose] public section

/-- Legacy: auto-wrap every `IO` def in this file. Prefer `@[profile]` on selected defs. -/
register_option profiler.instrument : Bool := {
  defValue := false
  descr := "Legacy file-wide IO auto-wrap. Prefer `profileRun` + `@[profile]` on hot defs only."
}

/-- When true with profiler.instrument, also wrap pure simple defs (uses unsafePerformIO while profiling is active). -/
register_option profiler.pure : Bool := {
  defValue := false
  descr := "Profile pure defs too (for ML/tensor stacks). Small overhead when profiling is active."
}
