# LeanProfiler

```lean
public import LeanProfiler

@[profile]
def unitTrainStepsFloat ... : IO ... := do
  nn.withModel mkModel fun model => do
    let L0 ← meanLossOnSamples ...
    for step in [0:steps] do
      optH.step sample
    let ids ← generateSampled ...

def main (args : List String) : IO UInt32 := do
  Common.runAnyOrFloat exeName args ...
```

## Three layers (pick what you need)

| Layer | What to do | What you get |
|-------|------------|--------------|
| **Import** | `public import LeanProfiler` | `main` prints summary + trace on exit |
| **`@[profile]`** | One attribute on the big function | Whole-function span **plus** auto-spans for IO calls inside (including `withModel` callbacks and `for` loops) |
| **`profile "name" do`** | Wrap a section manually | Named sub-span when you want finer control |

**TorchLean GPT2:** put `@[profile]` on `unitTrainStepsFloat` — that's it. You'll see `meanLossOnSamples`, `generateSampled`, `nn.eval1`, `optH.step`, etc. with call counts. Callback shells like `nn.withModel` and `runAnyOrFloat` are skipped automatically so time shows up in the real work. Add `profile "train" do` only when you want a custom label.

**Simple programs:** `main` auto-profiles top-level calls (e.g. `train`) when `profile_main` is on (default).

```lean
def train : IO Unit := do ...
def main : IO Unit := do
  train   -- auto-profiled
```

Disable auto-`main` with `set_option profile_main false`.

**Profile every function in a file:** set once at the top (per-file scope):

```lean
public import LeanProfiler
set_option profile_all true

def setup : IO Unit := do ...
def train : IO Unit := do ...
def report : IO Unit := do ...
```

Same rules as `@[profile]` — IO `def`s only; `main` gets teardown plus a span. Explicit `@[profile]` still wins.

## Other helpers

- **`profileLet`** — span around setup + side effects: `let x ← profileLet "open" (setup) fun x => ...`
- **`profile`** at end of a non-`main` IO path — force summary if teardown wouldn't run otherwise

Open traces at [ui.perfetto.dev](https://ui.perfetto.dev).
