# LeanProfiler

Import the library, mark IO functions with `@[profile]`, call `printSummary` when done.

```lean
import LeanProfiler

@[profile]
def train : IO Unit := do
  profile "loadData" do
    loadData

  profile "mid.train" do
    profile "attention" do
      runAttention

    profile "gelu" do
      runGelu

def main : IO Unit := do
  train
  printSummary
```

- **`@[profile]`** — whole function is one span (e.g. `train`).
- **`profile "name" do ...`** — manual sub-span anywhere inside that `do` (e.g. `attention`, `gelu`). Add as many labels as you want.

Each file that uses these needs `import LeanProfiler`.

IO `def`s only for `@[profile]`. Skips `partial` defs and `Except` / `Result` returns.

If you bind a value after setup + side effects, use `profileLet` instead of ending a block with `pure x`:

```lean
let sess ← profileLet "openSession" (EagerSession.new opts) fun sess =>
  sess.resetTape
```

Optional: `exportFlameGraph "trace.json"` then open at [ui.perfetto.dev](https://ui.perfetto.dev).
