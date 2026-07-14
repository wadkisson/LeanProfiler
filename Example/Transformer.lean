/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license.
-/
import LeanProfiler

/-!
# A small, real transformer — the LeanProfiler case study

This is a genuine (inference) forward pass of a decoder-style transformer block stack, written in
plain Lean on `FloatArray`: token+positional embedding, pre-LayerNorm, multi-head self-attention,
a GELU MLP, residuals, a final norm, and an output projection. There is no external dependency —
just arithmetic — so the numbers you profile are real Lean runtime, nothing else.

Every heavyweight kernel is a **pure** `FloatArray → FloatArray` function, wrapped with `spanPure`
so its evaluation time is attributed to its own span (see `LeanProfiler.spanPure`). The only thing
that differs between the `fast` and `naive` runs is the matmul loop order in `linear*`.
-/

namespace Demo

open LeanProfiler

/-- Model dimensions. -/
structure Config where
  vocab   : Nat
  dModel  : Nat
  dFF     : Nat
  nHeads  : Nat
  nLayers : Nat
  seqLen  : Nat

/-- A `FloatArray` of `n` zeros. -/
def zeros (n : Nat) : FloatArray := FloatArray.mk (Array.ofFn (n := n) fun _ => 0.0)

/-- Deterministic pseudo-random weights in `[-scale, scale)` from a `UInt64` hash of the index.
Built with `Array.ofFn` (a tight unboxed loop) rather than a `mut … push` loop. -/
def randVec (n seed : Nat) (scale : Float) : FloatArray :=
  FloatArray.mk <| Array.ofFn (n := n) fun i =>
    let h := (seed.toUInt64 + i.val.toUInt64 * 2654435761) * 6364136223846793005
             + 1442695040888963407
    (((h >>> 40).toFloat / 16777216.0) - 0.5) * 2.0 * scale

/-!
## The kernel under study: a dense linear layer `Y = X · Wᵀ`

`X` is `[seq × dIn]` row-major, `W` is `[dOut × dIn]` row-major, `Y` is `[seq × dOut]`.
Both versions compute the *identical* result with the *identical* number of multiply-adds and the
*identical* weight layout. They differ only in loop nesting, and therefore only in memory access
pattern.
-/

/-- Dense linear layer, accumulating each output into a register and writing it exactly once. -/
def linear (X W : FloatArray) (seq dIn dOut : Nat) : FloatArray := Id.run do
  let mut Y := zeros (seq * dOut)
  for s in [0:seq] do
    for o in [0:dOut] do
      let mut sum := 0.0
      for k in [0:dIn] do
        sum := sum + X.get! (s * dIn + k) * W.get! (o * dIn + k)
      Y := Y.set! (s * dOut + o) sum
  return Y

/-! ## The rest of the block (identical in both runs) -/

/-- Elementwise sum of two equal-length vectors (residual connections). -/
def addVec (a b : FloatArray) : FloatArray := Id.run do
  let mut y := a
  for i in [0:a.size] do
    y := y.set! i (a.get! i + b.get! i)
  return y

/-- Numerically-safe `tanh` via `exp` (avoids depending on `Float.tanh`). -/
@[inline] def ftanh (x : Float) : Float := 1.0 - 2.0 / (Float.exp (2.0 * x) + 1.0)

/-- Row-wise LayerNorm over the last dimension `d`, with affine `g`/`b`. -/
def layerNorm (X g b : FloatArray) (seq d : Nat) : FloatArray := Id.run do
  let dF := Float.ofNat d
  let mut Y := zeros (seq * d)
  for s in [0:seq] do
    let base := s * d
    let mut mean := 0.0
    for k in [0:d] do
      mean := mean + X.get! (base + k)
    mean := mean / dF
    let mut var := 0.0
    for k in [0:d] do
      let c := X.get! (base + k) - mean
      var := var + c * c
    let inv := 1.0 / Float.sqrt (var / dF + 1e-5)
    for k in [0:d] do
      let n := (X.get! (base + k) - mean) * inv
      Y := Y.set! (base + k) (n * g.get! k + b.get! k)
  return Y

/-- The type of an elementwise activation kernel, so the model can be run with either version. -/
abbrev Activation := FloatArray → FloatArray

/-- GELU (tanh approximation), elementwise value of `x`. -/
@[inline] def geluOf (x : Float) : Float :=
  0.5 * x * (1.0 + ftanh (0.7978845608028654 * (x + 0.044715 * x * x * x)))

/-- GELU built with a `mut … push` loop. Looks fine, but every computed element is boxed and pushed,
so the runtime never gets the tight unboxed loop it could — ~100x slower than `geluFast` here. -/
def geluSlow : Activation := fun X => Id.run do
  let mut Y := FloatArray.emptyWithCapacity X.size
  for i in [0:X.size] do
    Y := Y.push (geluOf (X.get! i))
  return Y

/-- The *same* GELU built with `Array.ofFn`, which compiles to a tight unboxed loop. Identical
output to `geluSlow`, ~100x faster. -/
def geluFast : Activation := fun X =>
  FloatArray.mk <| Array.ofFn (n := X.size) fun i => geluOf (X.get! i.val)

/-- Multi-head self-attention core: scores → softmax → weighted sum of values. `Q`, `K`, `V` are all
`[seq × d]`, split into `nHeads` heads of width `d / nHeads`. Returns the context `[seq × d]`. -/
def attnCore (Q K V : FloatArray) (seq d nHeads : Nat) : FloatArray := Id.run do
  let hd := d / nHeads
  let scale := 1.0 / Float.sqrt (Float.ofNat hd)
  let mut ctx := zeros (seq * d)
  for h in [0:nHeads] do
    let off := h * hd
    for s in [0:seq] do
      let mut scores := zeros seq
      let mut mx := -1e30
      for t in [0:seq] do
        let mut dot := 0.0
        for i in [0:hd] do
          dot := dot + Q.get! (s * d + off + i) * K.get! (t * d + off + i)
        dot := dot * scale
        scores := scores.set! t dot
        if dot > mx then mx := dot
      let mut denom := 0.0
      for t in [0:seq] do
        let e := Float.exp (scores.get! t - mx)
        scores := scores.set! t e
        denom := denom + e
      for i in [0:hd] do
        let mut acc := 0.0
        for t in [0:seq] do
          acc := acc + scores.get! t * V.get! (t * d + off + i)
        ctx := ctx.set! (s * d + off + i) (acc / denom)
  return ctx

/-! ## Weights and model -/

structure Block where
  wq : FloatArray
  wk : FloatArray
  wv : FloatArray
  wo : FloatArray
  w1 : FloatArray
  w2 : FloatArray
  ln1g : FloatArray
  ln1b : FloatArray
  ln2g : FloatArray
  ln2b : FloatArray
  deriving Inhabited

structure Model where
  cfg    : Config
  embed  : FloatArray
  pos    : FloatArray
  blocks : Array Block
  lnFg   : FloatArray
  lnFb   : FloatArray
  wOut   : FloatArray

/-- A `FloatArray` of `n` ones. -/
def onesVec (n : Nat) : FloatArray := FloatArray.mk (Array.ofFn (n := n) fun _ => 1.0)

/-- Derive a distinct seed for each tensor. -/
@[inline] def seedFor (base tag : Nat) : Nat := base + tag * 2654435761

/-- Build a deterministic model from a seed. Weights are small so activations stay finite. -/
def buildModel (cfg : Config) (seed : Nat) : Model := Id.run do
  let d := cfg.dModel
  let scale := 0.02
  let mut blocks : Array Block := #[]
  for i in [0:cfg.nLayers] do
    let b : Block :=
      { wq := randVec (d * d) (seedFor seed (i*10+1)) scale
        wk := randVec (d * d) (seedFor seed (i*10+2)) scale
        wv := randVec (d * d) (seedFor seed (i*10+3)) scale
        wo := randVec (d * d) (seedFor seed (i*10+4)) scale
        w1 := randVec (cfg.dFF * d) (seedFor seed (i*10+5)) scale
        w2 := randVec (d * cfg.dFF) (seedFor seed (i*10+6)) scale
        ln1g := onesVec d
        ln1b := zeros d
        ln2g := onesVec d
        ln2b := zeros d }
    blocks := blocks.push b
  return {
    cfg := cfg
    embed := randVec (cfg.vocab * d) (seedFor seed 7001) scale
    pos := randVec (cfg.seqLen * d) (seedFor seed 7002) scale
    blocks := blocks
    lnFg := onesVec d
    lnFb := zeros d
    wOut := randVec (cfg.vocab * d) (seedFor seed 7003) scale }

/-- Sum every weight, forcing the whole (lazily-built) model into memory. -/
def forceModel (m : Model) : Float := Id.run do
  let sum := fun (a : FloatArray) => Id.run do
    let mut s := 0.0
    for i in [0:a.size] do s := s + a.get! i
    return s
  let mut s := sum m.embed + sum m.pos + sum m.wOut + sum m.lnFg + sum m.lnFb
  for b in m.blocks do
    s := s + sum b.wq + sum b.wk + sum b.wv + sum b.wo + sum b.w1 + sum b.w2
  return s

/-- Build **and materialize** the model once, returning a shared value.

`buildModel` is pure, so `let model := buildModel …` merely creates a thunk; if that thunk is then
used from a single call site, the Lean compiler may inline it and *recompute the weights on every
access* deep inside the forward pass (in this demo that made the forward pass ~11x slower, with the
work landing outside every span). Forcing it here with `spanPure` evaluates the weights exactly once
and shares the result — the realistic "load the checkpoint once" step — and attributes that cost to a
`load.weights` span. -/
def loadWeights (cfg : Config) (seed : Nat) : IO Model := do
  let m := buildModel cfg seed
  -- Deep-force every weight inside the span; `m` is used again below, so it is shared, not recomputed.
  let cs ← spanPure "load.weights" (fun _ => forceModel m) { phase := some "setup" }
  if cs.isNaN then throw (IO.userError "model produced NaN weights")
  return m

/-- Token + positional embedding lookup, producing `[seq × d]`. -/
def embedTokens (m : Model) (tokens : Array Nat) (seq d : Nat) : FloatArray := Id.run do
  let mut X := zeros (seq * d)
  for s in [0:seq] do
    let tok := tokens[s]!
    for k in [0:d] do
      X := X.set! (s * d + k) (m.embed.get! (tok * d + k) + m.pos.get! (s * d + k))
  return X

/-! ## Instrumented forward pass

Each kernel is a pure function wrapped in `spanPure`, so its evaluation is forced *inside* its span
and attributed correctly. The whole block is a `span` so the report nests kernels under it. -/

def blockForward (act : Activation) (blk : Block) (cfg : Config) (X : FloatArray) : IO FloatArray := do
  let seq := cfg.seqLen
  let d := cfg.dModel
  let fwd : Metadata := { phase := some "forward" }
  let normed  ← spanPure "ln1"         (fun _ => layerNorm X blk.ln1g blk.ln1b seq d) fwd
  let q       ← spanPure "attn.proj.q" (fun _ => linear normed blk.wq seq d d) fwd
  let k       ← spanPure "attn.proj.k" (fun _ => linear normed blk.wk seq d d) fwd
  let v       ← spanPure "attn.proj.v" (fun _ => linear normed blk.wv seq d d) fwd
  let core    ← spanPure "attn.core"   (fun _ => attnCore q k v seq d cfg.nHeads) fwd
  let attnOut ← spanPure "attn.proj.o" (fun _ => linear core blk.wo seq d d) fwd
  let X       ← spanPure "residual1"   (fun _ => addVec X attnOut) fwd
  let normed2 ← spanPure "ln2"         (fun _ => layerNorm X blk.ln2g blk.ln2b seq d) fwd
  let hidden  ← spanPure "mlp.fc1"     (fun _ => linear normed2 blk.w1 seq d cfg.dFF) fwd
  let acted   ← spanPure "mlp.gelu"    (fun _ => act hidden) fwd
  let mlpOut  ← spanPure "mlp.fc2"     (fun _ => linear acted blk.w2 seq cfg.dFF d) fwd
  let X       ← spanPure "residual2"   (fun _ => addVec X mlpOut) fwd
  return X

/-- Run the model forward and return a checksum of the logits (forces the whole computation). -/
def forward (act : Activation) (model : Model) (tokens : Array Nat) : IO Float := do
  let cfg := model.cfg
  let seq := cfg.seqLen
  let d := cfg.dModel
  let fwd : Metadata := { phase := some "forward" }
  let mut X ← spanPure "embed" (fun _ => embedTokens model tokens seq d) fwd
  for i in [0:cfg.nLayers] do
    X ← span s!"block{i}" (metadata := fwd) do
      blockForward act model.blocks[i]! cfg X
  X ← spanPure "ln.final" (fun _ => layerNorm X model.lnFg model.lnFb seq d) fwd
  let logits ← spanPure "logits" (fun _ => linear X model.wOut seq d cfg.vocab) fwd
  spanPure "checksum" (fun _ => Id.run do
    let mut acc := 0.0
    for i in [0:logits.size] do
      acc := acc + logits.get! i
    return acc) fwd

end Demo
