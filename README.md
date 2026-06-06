# LeanProfiler

```lean
public import LeanProfiler

@[profile]
def train : IO Unit := do
  profile "loadData" do
    loadData

  profile "forward" do
    profile "attention" do
      runAttention

def main : IO Unit := do
  train
  profile
```

- **`@[profile]`** — whole function is one span.
- **`profile "name" do ...`** — manual sub-span inside a `do` block.
- **`profile`** — print summary + trace (`IO Unit` mains).
- **`profile code`** — same, then return `code` (`IO UInt32` mains — no separate `pure`).

Use **`public import LeanProfiler`** in modules that use `@[profile]`.

## CLI / exit-code mains (TorchLean-style)

```lean
def main (args : List String) : IO UInt32 := do
  let code ← Common.runAnyOrFloat exeName args ...
  profile code
```

Or wrap the whole CLI call:

```lean
def main (args : List String) : IO UInt32 :=
  profileAfter do
    Common.runAnyOrFloat exeName args ...
```

Inside a callback (`IO Unit`):

```lean
(floatK := fun opts rest => do
  let _ ← unitTrainStepsFloat opts input train
  profile)
```

If you bind a value after setup + side effects, use `profileLet`:

```lean
let sess ← profileLet "openSession" (EagerSession.new opts) fun sess =>
  sess.resetTape
```

Open traces at [ui.perfetto.dev](https://ui.perfetto.dev).
