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
```

- **`@[profile]`** — whole function is one span.
- **`profile "name" do ...`** — manual sub-span inside a `do` block.
- **`main`** — auto-wrapped: summary + trace run when the program exits (any `IO` return type).

Use **`public import LeanProfiler`** in modules that use `@[profile]`.

No manual close step on `main`. TorchLean-style CLIs stay as-is:

```lean
def main (args : List String) : IO UInt32 := do
  Common.runAnyOrFloat exeName args ...
```

If `main` is not your entry point (e.g. training runs inside a callback only), call **`profile`** once at the end of that `IO Unit` path.

Optional: **`profileAfter do ...`** if you need an explicit wrapper instead of relying on auto-`main`.

If you bind a value after setup + side effects, use **`profileLet`**:

```lean
let sess ← profileLet "openSession" (EagerSession.new opts) fun sess =>
  sess.resetTape
```

Open traces at [ui.perfetto.dev](https://ui.perfetto.dev).
