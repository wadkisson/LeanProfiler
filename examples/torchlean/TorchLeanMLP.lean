/-
Copyright (c) 2026 LeanProfiler contributors
Released under MIT license as described in the file LICENSE.
-/

module

public import LeanProfiler
public import NN

/-!
# Profiling Scalable TorchLean MLP Training

This example profiles a shape-checked TorchLean MLP without fixing the model size or execution
target in its source. Input width, hidden width, hidden-layer count, output width, batch size,
optimizer, scalar mode, backend, and device are command-line choices. The defaults describe a
100,687,872-parameter MLP and select CUDA, while smaller CPU runs use the same program.

Build and profile a CUDA run from this directory:

```bash
lake -R -K cuda=true build torchlean-mlp-profile
LEAN_PROFILE=1 LEAN_PROFILE_OUT=build/torchlean-mlp-100m.json \
  lake -R -K cuda=true exe torchlean-mlp-profile --device cuda
```

For a quick CPU run, override the scale as well as the device:

```bash
LEAN_PROFILE=1 lake exe torchlean-mlp-profile \
  --device cpu --input 128 --hidden 256 --layers 3 --output 64 --batch 8 --steps 2
```

Run with `--help` for every workload and TorchLean runtime option.
-/

@[expose] public section

open LeanProfiler
open TorchLean

namespace TorchLeanMLP

def executableName := "torchlean-mlp-profile"

/-- Scalable model and training choices, independent of the TorchLean execution runtime. -/
structure WorkloadConfig where
  /-- Feature count on the input's last axis. -/
  inputDim : Nat := 4096
  /-- Width shared by the hidden layers. -/
  hiddenDim : Nat := 4096
  /-- Number of hidden affine layers. Zero constructs a direct input-to-output model. -/
  hiddenLayers : Nat := 5
  /-- Feature count on the output's last axis. -/
  outputDim : Nat := 4096
  /-- Number of examples evaluated by each shape-checked forward pass. -/
  batchSize : Nat := 16
  /-- Number of optimizer updates. -/
  steps : Nat := 1
  /-- Step interval for TorchLean loss logging; zero disables it. -/
  logEvery : Nat := 1
  /-- Base seed for parameters and generated data. -/
  seed : Nat := 0
  /-- Optimizer algorithm selected through TorchLean's public optimizer registry. -/
  optimizer : optim.Kind := .adam
  /-- Learning rate supplied to the selected optimizer. -/
  learningRate : Float := 1e-3
  deriving Repr

namespace WorkloadConfig

/-- Shape of one full input batch. Linear layers preserve the leading batch axis. -/
def inputShape (cfg : WorkloadConfig) : Shape :=
  (Spec.Shape.dim cfg.batchSize .scalar).appendDim cfg.inputDim

/-- Shape of one full output batch. -/
def outputShape (cfg : WorkloadConfig) : Shape :=
  (Spec.Shape.dim cfg.batchSize .scalar).appendDim cfg.outputDim

/-- Exact number of trainable weights and biases in the selected MLP. -/
def parameterCount (cfg : WorkloadConfig) : Nat :=
  if cfg.hiddenLayers = 0 then
    cfg.inputDim * cfg.outputDim + cfg.outputDim
  else
    let first := cfg.inputDim * cfg.hiddenDim + cfg.hiddenDim
    let middle := (cfg.hiddenLayers - 1) *
      (cfg.hiddenDim * cfg.hiddenDim + cfg.hiddenDim)
    let last := cfg.hiddenDim * cfg.outputDim + cfg.outputDim
    first + middle + last

def architectureName (cfg : WorkloadConfig) : String :=
  s!"mlp.{cfg.inputDim}x{cfg.hiddenDim}x{cfg.hiddenLayers}x{cfg.outputDim}"

end WorkloadConfig

/-- Compose `count` hidden-width affine/ReLU blocks. -/
def hiddenTail (leading : Shape) (width : Nat) :
    (count : Nat) → nn.M (nn.Sequential
      (leading.appendDim width) (leading.appendDim width))
  | 0 => nn.lift (.id (leading.appendDim width))
  | count + 1 => nn.Sequential![
      nn.linear width width leading,
      nn.relu,
      hiddenTail leading width count
    ]

/-- Build an MLP while keeping arbitrary leading dimensions unchanged. -/
def modelWith (leading : Shape) (inputDim hiddenDim hiddenLayers outputDim : Nat) :
    nn.M (nn.Sequential
      (leading.appendDim inputDim) (leading.appendDim outputDim)) :=
  match hiddenLayers with
  | 0 => nn.linear inputDim outputDim leading
  | hiddenTailCount + 1 => nn.Sequential![
      nn.linear inputDim hiddenDim leading,
      nn.relu,
      hiddenTail leading hiddenDim hiddenTailCount,
      nn.linear hiddenDim outputDim leading
    ]

/-- Build the MLP selected by `cfg`; all dimensions remain visible in its Lean type. -/
def model (cfg : WorkloadConfig) :
    nn.M (nn.Sequential cfg.inputShape cfg.outputShape) :=
  modelWith (.dim cfg.batchSize .scalar) cfg.inputDim cfg.hiddenDim
    cfg.hiddenLayers cfg.outputDim

def generatedValue (seed index : Nat) : Float :=
  let raw := (index * 37 + seed * 101 + 17) % 1021
  Float.ofNat raw / 510.0 - 1.0

/-- One generated full-batch sample, materialized at the scalar type selected by the runtime. -/
def dataset (cfg : WorkloadConfig) : Trainer.Dataset cfg.inputShape cfg.outputShape :=
  Data.singleton fun {α} _ _ =>
    let x := Tensor.tensorFGenShape! (α := α) Runtime.ofFloat cfg.inputShape
      (generatedValue cfg.seed)
    let y := Tensor.tensorFGenShape! (α := α) Runtime.ofFloat cfg.outputShape
      (generatedValue (cfg.seed + 1))
    Sample.mk x y

/-- Deterministic input used for the post-training inference span. -/
def inferenceInput (cfg : WorkloadConfig) : Tensor.T Float cfg.inputShape :=
  Tensor.tensorFGenShape! (α := Float) id cfg.inputShape
    (generatedValue (cfg.seed + 2))

def dtypeName : Runtime.DType → String
  | .float => "float"
  | .real => "real"
  | .float32 { mode := .fp32 } => "fp32"
  | .float32 { mode := .ieee754Exec } => "ieee754exec"
  | .complex _ => "complex"

def backendName : Runtime.Backend → String
  | .eager => "eager"
  | .compiled => "compiled"

/-- Profiler metadata derived from the actual workload and TorchLean runtime selection. -/
def runtimeMetadata (cfg : WorkloadConfig) (runtime : Trainer.RunConfig)
    (phase : String) : Metadata :=
  { phase := some phase
    backend := some (backendName runtime.backend)
    dtype := some (dtypeName runtime.dtype)
    device := some runtime.toOptions.deviceName
    moduleName := some cfg.architectureName
    inputShapes := #[reprStr cfg.inputShape]
    outputShape := some (reprStr cfg.outputShape) }

def help : String := String.intercalate "\n"
  [ "Profile a configurable, shape-checked TorchLean MLP."
  , ""
  , "Usage:"
  , "  lake exe torchlean-mlp-profile [workload options] [runtime options]"
  , ""
  , "Workload options:"
  , "  --input N       input feature count (default: 4096)"
  , "  --hidden N      hidden feature count (default: 4096)"
  , "  --layers N      hidden affine-layer count (default: 5)"
  , "  --output N      output feature count (default: 4096)"
  , "  --batch N       examples per typed forward pass (default: 16)"
  , "  --steps N       optimizer updates (default: 1)"
  , "  --log-every N   loss logging interval; 0 disables it (default: 1)"
  , "  --seed N        model and generated-data seed (default: 0)"
  , "  --optim NAME    sgd, adagrad, rmsprop, adam, adamw, or adadelta (default: adam)"
  , "  --lr FLOAT      learning rate (default: 0.001)"
  , ""
  , "TorchLean runtime options:"
  , "  --device NAME   cpu, cuda, rocm, metal, wasm, tpu, trainium, custom, or external"
  , "                  (default here: cuda; unavailable runtimes fail explicitly)"
  , "  --backend NAME  eager or compiled (default: eager)"
  , "  --dtype NAME    float, ieee754exec, or a proof-only scalar mode (default: float)"
  , "  --show-backend  print the selected backend capsule"
  , "  -h, --help      show this message"
  , ""
  , "The default dimensions contain 100,687,872 trainable parameters. Every dimension above can be"
  , "changed independently; the model, dataset, profiler metadata, and parameter count follow the same"
  , "configuration." ]

def parseOptimizer (args : List String) : IO (optim.Kind × List String) := do
  let (name?, rest) ← CLI.orThrow executableName <|
    TorchLean.CLI.takeFlagValueOnce args "optim"
  match name? with
  | none => pure (.adam, rest)
  | some name =>
      let kind ← CLI.orThrow executableName <| optim.Kind.parse name
      pure (kind, rest)

/-- Parse model scale first, then delegate execution flags to TorchLean's runtime parser. -/
def parse (rawArgs : List String) : IO (Option (WorkloadConfig × Trainer.RunConfig)) := do
  let args := TorchLean.CLI.dropDashDash rawArgs
  if TorchLean.CLI.hasHelp args then
    IO.println help
    pure none
  else
    let (inputDim, args) ← CLI.positiveNatFlag executableName args "input" 4096
    let (hiddenDim, args) ← CLI.positiveNatFlag executableName args "hidden" 4096
    let (hiddenLayers, args) ← CLI.natFlagDefault executableName args "layers" 5
    let (outputDim, args) ← CLI.positiveNatFlag executableName args "output" 4096
    let (batchSize, args) ← CLI.positiveNatFlag executableName args "batch" 16
    let (steps, args) ← CLI.positiveNatFlag executableName args "steps" 1
    let (logEvery, args) ← CLI.natFlagDefault executableName args "log-every" 1
    let (seed, args) ← CLI.seed executableName args 0
    let (optimizer, args) ← parseOptimizer args
    let (learningRate, args) ← CLI.floatFlagDefault executableName args "lr" 1e-3
    let workload : WorkloadConfig :=
      { inputDim, hiddenDim, hiddenLayers, outputDim, batchSize, steps, logEvery,
        seed, optimizer, learningRate }
    let baseRuntime : Trainer.RunConfig :=
      { optimizer := optimizer.toOptimizer learningRate
        dtype := .float
        backend := .eager
        device := .cuda }
    let (runtime, rest) ← CLI.orThrow executableName <|
      Trainer.RunConfig.parseRuntimeArgs args baseRuntime
    CLI.requireNoArgs executableName rest
    pure (some (workload, runtime))

def run (cfg : WorkloadConfig) (runtime : Trainer.RunConfig) : IO Unit := do
  IO.println s!"model: {cfg.architectureName}"
  IO.println s!"parameters: {cfg.parameterCount}"
  IO.println s!"batch: {cfg.batchSize}; steps: {cfg.steps}; optimizer: {cfg.optimizer.name}"
  IO.println s!"runtime: {runtime.toOptions.deviceName}/{backendName runtime.backend}/{dtypeName runtime.dtype}"

  let trainer := Trainer.new (model cfg)
    (Trainer.Config.fromRunConfig runtime (.regression) cfg.seed)
  let trained ← span "torchlean.train.mlp"
      (metadata := runtimeMetadata cfg runtime "training") do
    trainer.train (dataset cfg)
      { steps := cfg.steps, batchSize := 1, logEvery := cfg.logEvery }

  let _ ← span "torchlean.predict.trained"
      (metadata := runtimeMetadata cfg runtime "inference") do
    trained.predict (inferenceInput cfg)
  IO.println s!"loss: {trained.report.before} -> {trained.report.after}"

end TorchLeanMLP

profiled_main def main (args : List String) : IO Unit := do
  match ← TorchLeanMLP.parse args with
  | none => pure ()
  | some (cfg, runtime) => TorchLeanMLP.run cfg runtime
