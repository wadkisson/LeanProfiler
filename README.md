# LeanProfiler

Import the library, mark IO functions with `@[profile]`, define `main` as usual.

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
- **`def main`** — auto-wrapped on exit: Perfetto trace (`build/leanprofiler-trace.json`) + text summary. Works for `IO Unit`, `IO UInt32`, etc.

Use **`public import LeanProfiler`** in modules that use `@[profile]` (attributes expand at elaboration time).

## CLI / exit-code mains (TorchLean-style)

Import LeanProfiler in the executable module; `main` is wrapped automatically — no trailing `printSummary`:

```lean
public import LeanProfiler

def main (args : List String) : IO UInt32 := do
  Common.runAnyOrFloat exeName args
    (preferFloat := ...)
    (banner := ...)
    (anyK := fun ... => ...)
    (floatK := fun opts rest => do
      let _ ← unitTrainStepsFloat opts input train)
```

Optional: `exportFlameGraph "custom.json"` inside `main` for a different path (runs before the auto-export).

If you bind a value after setup + side effects, use `profileLet` instead of ending a block with `pure x`:

```lean
let sess ← profileLet "openSession" (EagerSession.new opts) fun sess =>
  sess.resetTape
```

Open traces at [ui.perfetto.dev](https://ui.perfetto.dev).
