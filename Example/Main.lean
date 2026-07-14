/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
-/
import LeanProfiler
import Example.Transformer

open LeanProfiler Demo

/-!
# Transformer profiling demo

```bash
LEAN_PROFILE=1 lake exe transformer-demo slow   # GELU built with a `mut … push` loop
LEAN_PROFILE=1 lake exe transformer-demo fast    # the same GELU built with `Array.ofFn`
```

Both modes produce the *identical* logits checksum; only the activation kernel's implementation
differs. `profiled_main` handles `clear` on entry and `finish .all` on exit, gated on `LEAN_PROFILE`.
Without the env var it runs the model with zero profiling overhead.
-/

def config : Config :=
  { vocab := 512, dModel := 256, dFF := 512, nHeads := 4, nLayers := 4, seqLen := 32 }

profiled_main def main (args : List String) : IO Unit := do
  let mode := args.head?.getD "fast"
  let act : Activation := if mode == "slow" then geluSlow else geluFast
  let model ← loadWeights config 12345
  let tokens := (Array.range config.seqLen).map (fun i => (i * 7 + 3) % config.vocab)
  IO.println s!"transformer-demo: mode={mode}  \
    (dModel={config.dModel} dFF={config.dFF} heads={config.nHeads} \
    layers={config.nLayers} seq={config.seqLen})"
  let checksum ← forward act model tokens
  IO.println s!"logits checksum = {checksum}"
