import Lake

open Lake DSL
open System

/-!
This example is a separate package so LeanProfiler does not acquire TorchLean's dependency graph.
The runtime-related Lake options are forwarded explicitly: Lake does not otherwise pass arbitrary
`-K` options or a dependency's package-level native linker flags to a downstream executable.
-/

private def cudaEnabled : Bool :=
  match get_config? cuda with
  | some value => value == "true" || value == "1"
  | none => false

private def cudaHome : String :=
  (get_config? cuda_home).getD "/usr/local/cuda"

private def libtorchEnabled : Bool :=
  match get_config? libtorch with
  | some value => value == "true" || value == "1"
  | none => false

private def libtorchHome : String :=
  (get_config? libtorch_home).getD "libtorch"

private def nativeLinkArgs : Array String :=
  if cudaEnabled then
    let cudaArgs := #[
      "-L", s!"{cudaHome}/lib64", "-lcudart", "-lcublas", "-lcufft",
      "-Wl,-rpath," ++ s!"{cudaHome}/lib64"
    ]
    if libtorchEnabled then
      cudaArgs.push ("-Wl,-rpath," ++ s!"{libtorchHome}/lib")
    else
      cudaArgs
  else if Platform.isWindows || Platform.isOSX then
    #[]
  else
    #["-lm", "-lstdc++"]

package LeanProfilerTorchLeanExample where
  version := v!"0.1.0"
  moreLinkArgs := nativeLinkArgs

require LeanProfiler from "../.."

require TorchLean from git
  "https://github.com/lean-dojo/TorchLean.git" @ "5f7d3ee" with
  ((∅ : Lean.NameMap String) |>.insert `cuda ((get_config? cuda).getD "false")
      |>.insert `cuda_home ((get_config? cuda_home).getD "/usr/local/cuda")
      |>.insert `libtorch ((get_config? libtorch).getD "false")
      |>.insert `libtorch_home ((get_config? libtorch_home).getD ""))

@[default_target]
lean_exe «torchlean-mlp-profile» where
  root := `TorchLeanMLP
