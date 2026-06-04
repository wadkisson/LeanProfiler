module

public import Lean.LabelAttribute

@[expose] public section

/-- Mark this `def` for timing (wrapped with `withProfileWhenActive`; active only inside `profileRun`). -/
register_label_attr profile
