module

public import Lean

@[expose] public section

/-- When true, `@[profile]` rewrites IO `def`s to wrap the body in `withProfile`. -/
register_option profiler.rewrite : Bool := {
  defValue := false
  descr := "Rewrite `@[profile]` IO defs to use `withProfile` automatically."
}
