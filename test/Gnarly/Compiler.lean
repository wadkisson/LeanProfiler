import LeanProfiler
import test.Gnarly.Core

set_option profiler.rewrite true

@[profile]
def lexTokens (src : String) : IO (List String) := do
  pulse "compiler.lex" 2
  pure (src.splitOn " ")

@[profile]
def parseModule (tokens : List String) : IO (List String) := do
  pulse "compiler.parse" 3
  pure (tokens.map (fun t => s!"ast:{t}"))

@[profile]
def elaborateDecls (asts : List String) : IO (List String) := do
  let mut out : List String := []
  for ast in asts do
    pulse s!"compiler.elab.{ast.length}" 1
    out := s!"typed:{ast}" :: out
  pure out.reverse

@[profile]
def codegen (typed : List String) : IO (List String) := do
  let mut out : List String := []
  for t in typed do
    pulse "compiler.codegen" 2
    out := s!"obj:{t}" :: out
  pure out.reverse

def compileSource (src : String) : IO (List String) := do
  let toks ← lexTokens src
  let asts ← parseModule toks
  let typed ← elaborateDecls asts
  codegen typed

@[profile]
def compileBatch (sources : List String) : IO Nat := do
  let mut count := 0
  for src in sources do
    let objs ← withProfile s!"compiler.batch.{count}" do
      compileSource src
    count := count + objs.length
  pure count

def fakeSources : List String := [
  "def foo := 1",
  "def bar x := x + 1",
  "structure Point where x y : Nat",
  "def baz := foo + bar 2",
  "inductive Color | red | green | blue"
]
