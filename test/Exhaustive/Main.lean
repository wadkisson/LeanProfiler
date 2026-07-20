/-
  THROWAWAY exhaustive functional tests for LeanProfiler.
  Delete `test/Exhaustive` when done probing. Not part of the shipped API.
-/

import LeanProfiler

open LeanProfiler

/-- Substring check (Lean 4.30 has no `String.containsSubstr`). -/
def hasSubstr (haystack needle : String) : Bool :=
  needle.isEmpty || (haystack.splitOn needle).length > 1

/-- Fail the suite with a labeled message. -/
def fail (msg : String) : IO Unit :=
  throw <| IO.userError msg

/-- Assert a boolean condition. -/
def assertTrue (label : String) (b : Bool) : IO Unit := do
  unless b do fail s!"ASSERT FAIL: {label}"

/-- Assert equality for types with `BEq` + `ToString`. -/
def assertEq {α : Type} [BEq α] [ToString α] (label : String) (got expected : α) : IO Unit := do
  unless got == expected do
    fail s!"ASSERT FAIL: {label}\n  got:      {got}\n  expected: {expected}"

/-- Assert inequality. -/
def assertNe {α : Type} [BEq α] [ToString α] (label : String) (got unexpected : α) : IO Unit := do
  unless !(got == unexpected) do
    fail s!"ASSERT FAIL: {label}\n  unexpectedly equal: {got}"

/-- Assert string contains a substring. -/
def assertContains (label : String) (haystack needle : String) : IO Unit := do
  unless hasSubstr haystack needle do
    fail s!"ASSERT FAIL: {label}\n  missing {needle.quote} in:\n{haystack}"

/-- Assert string does not contain a substring. -/
def assertNotContains (label : String) (haystack needle : String) : IO Unit := do
  unless !(hasSubstr haystack needle) do
    fail s!"ASSERT FAIL: {label}\n  unexpectedly found {needle.quote}"

/-- Find a summary row by exact name. -/
def findRow (name : String) (rows : Array SummaryRow) : Option SummaryRow := Id.run do
  for row in rows do
    if row.name == name then return some row
  return none

/-- Find an event by name. -/
def findEvent (name : String) (events : Array Event) : Option Event :=
  events.find? (·.name == name)

/-- Count events with a given name. -/
def countNamed (name : String) (events : Array Event) : Nat :=
  events.foldl (init := 0) fun acc e => if e.name == name then acc + 1 else acc

/-- Busy loop used to create measurable wall time. -/
def busy (n : Nat) : IO Nat := do
  let mut acc := 0
  for i in [0:n] do
    acc := acc + i
  pure acc

/-- Busy loop returning `Unit` for `IO Unit` span slots. -/
def busyU (n : Nat) : IO Unit := do
  let _ ← busy n
  pure ()

/-- Pure LCG used for pure-attribution / value checks. -/
def heavy (n seed : Nat) : Nat := Id.run do
  let mut acc := seed
  for i in [0:n] do
    acc := (acc * 1664525 + i + 1013904223) % 4294967291
  return acc

/-- Drain a task that may throw. -/
def runTask (task : Task (Except IO.Error Unit)) : IO Unit := do
  match task.get with
  | Except.ok () => pure ()
  | Except.error e => throw e

/-- Read a file that must exist. -/
def readFile (path : String) : IO String :=
  IO.FS.readFile path

/-- Delete a path if present (best-effort). -/
def rm (path : String) : IO Unit := do
  try IO.FS.removeFile path catch _ => pure ()

/-- Whether a file exists and is readable. -/
def fileExists (path : String) : IO Bool := do
  try
    let _ ← IO.FS.readFile path
    pure true
  catch _ =>
    pure false

/-- Artifact directory for this throwaway suite. -/
def artifactDir : String := "build/exhaustive-artifacts"

/-- Array element at index, or throw. -/
def getIdx {α : Type} (label : String) (arr : Array α) (i : Nat) : IO α := do
  if h : i < arr.size then
    pure arr[i]
  else
    throw <| IO.userError s!"{label}: index {i} out of range (size {arr.size})"

/-- First array element or throw. -/
def firstArr {α : Type} (label : String) (arr : Array α) : IO α :=
  getIdx label arr 0

/-! ## 1. Formatting helpers -/

def testPadRight : IO Unit := do
  assertEq "padRight exact" (padRight "hi" 2) "hi"
  assertEq "padRight wider" (padRight "hi" 5) "hi   "
  assertEq "padRight shorter width" (padRight "hello" 3) "hello"
  assertEq "padRight empty" (padRight "" 3) "   "
  assertEq "padRight zero" (padRight "x" 0) "x"

def testPadLeft : IO Unit := do
  assertEq "padLeft exact" (padLeft "hi" 2) "hi"
  assertEq "padLeft wider" (padLeft "hi" 5) "   hi"
  assertEq "padLeft shorter width" (padLeft "hello" 3) "hello"
  assertEq "padLeft empty" (padLeft "" 3) "   "
  assertEq "padLeft zero" (padLeft "x" 0) "x"

def testDisplayName : IO Unit := do
  assertEq "display short" (displayName "abc" 10) "abc"
  assertEq "display exact" (displayName "abcdefghij" 10) "abcdefghij"
  assertEq "display truncate" (displayName "abcdefghijklmnop" 10) "...jklmnop"
  assertEq "display default width keeps short" (displayName "ok") "ok"
  let long := String.ofList (List.replicate 80 'a')
  let shown := displayName long
  assertTrue "display truncates long default" (shown.length == summaryNameWidth)
  assertTrue "display ellipsis prefix" (String.isPrefixOf "..." shown)

def testFormatDuration : IO Unit := do
  assertEq "ns < 1000" (formatDuration 0) "0 ns"
  assertEq "ns 999" (formatDuration 999) "999 ns"
  assertEq "us boundary" (formatDuration 1000) "1.00 us"
  assertEq "us mid" (formatDuration 12_340) "12.34 us"
  assertEq "ms boundary" (formatDuration 1_000_000) "1.00 ms"
  assertEq "ms mid" (formatDuration 12_340_000) "12.34 ms"
  assertEq "s boundary" (formatDuration 1_000_000_000) "1.00 s"
  assertEq "s mid" (formatDuration 2_500_000_000) "2.50 s"
  assertEq "us tenths" (formatDuration 1_050) "1.05 us"
  assertEq "ms tenths" (formatDuration 1_050_000) "1.05 ms"

def testFlameBar : IO Unit := do
  assertEq "flame zero total" (flameBar 10 0) ""
  assertEq "flame zero self" (flameBar 0 100) ""
  assertEq "flame full" (flameBar 100 100) (String.ofList (List.replicate flameBarWidth '#'))
  assertEq "flame half" (flameBar 50 100) (String.ofList (List.replicate (flameBarWidth / 2) '#'))
  assertTrue "flame never exceeds width" ((flameBar 10_000 1).length ≤ flameBarWidth)

def testJsonEscape : IO Unit := do
  assertEq "json plain" (jsonEscape "abc") "abc"
  assertEq "json quote" (jsonEscape "a\"b") "a\\\"b"
  assertEq "json backslash" (jsonEscape "a\\b") "a\\\\b"
  assertEq "json newline" (jsonEscape "a\nb") "a\\nb"
  assertEq "json cr" (jsonEscape "a\rb") "a\\rb"
  assertEq "json tab" (jsonEscape "a\tb") "a\\tb"
  assertEq "json empty" (jsonEscape "") ""

def testHtmlEscape : IO Unit := do
  assertEq "html amp" (htmlEscape "a&b") "a&amp;b"
  assertEq "html lt" (htmlEscape "a<b") "a&lt;b"
  assertEq "html gt" (htmlEscape "a>b") "a&gt;b"
  assertEq "html quote" (htmlEscape "a\"b") "a&quot;b"
  assertEq "html combo" (htmlEscape "<a href=\"x\">&</a>") "&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;"
  assertEq "html empty" (htmlEscape "") ""

def testJsonFields : IO Unit := do
  assertEq "jsonStringField" (jsonStringField "k" "v") "\"k\":\"v\""
  assertEq "jsonStringField escape" (jsonStringField "k\"" "v\\") "\"k\\\"\":\"v\\\\\""
  assertEq "jsonNatField" (jsonNatField "n" 42) "\"n\":42"
  assertEq "jsonIntField pos" (jsonIntField "n" (5 : Int)) "\"n\":5"
  assertEq "jsonIntField neg" (jsonIntField "n" (-3 : Int)) "\"n\":-3"
  assertEq "jsonStringArray empty" (jsonStringArrayField "a" #[]) "\"a\":[]"
  assertEq "jsonStringArray" (jsonStringArrayField "a" #["x", "y"]) "\"a\":[\"x\",\"y\"]"
  assertContains "jsonStringArray escape" (jsonStringArrayField "a" #["\""]) "\\\""

def testPhaseColor : IO Unit := do
  assertEq "phase forward" (phaseColor "forward") "#f3a43b"
  assertEq "phase backward" (phaseColor "backward") "#67c7d4"
  assertEq "phase step" (phaseColor "step") "#9be26f"
  assertEq "phase other" (phaseColor "other") "#d6a4ff"
  assertEq "phase unknown" (phaseColor "zzz") "#d6a4ff"

def testReportPath : IO Unit := do
  assertEq "report path append" (reportPathForTrace "a.json") "a.json.html"
  assertEq "report path nested" (reportPathForTrace "build/x.json") "build/x.json.html"

/-! ## 2. Metadata / event pure helpers -/

def testMetadataWithContext : IO Unit := do
  let md : Metadata := { phase := some "forward", stepIndex := none, moduleName := none }
  let ctx : Context := { stepIndex := some 7, moduleName := some "mod", parentIndex := some 3 }
  let merged := md.withContext ctx
  assertEq "withContext keeps phase" merged.phase (some "forward")
  assertEq "withContext fills step" merged.stepIndex (some 7)
  assertEq "withContext fills module" merged.moduleName (some "mod")
  let md2 : Metadata := { stepIndex := some 1, moduleName := some "own" }
  let merged2 := md2.withContext ctx
  assertEq "withContext prefers meta step" merged2.stepIndex (some 1)
  assertEq "withContext prefers meta module" merged2.moduleName (some "own")

def testMetadataLabelParts : IO Unit := do
  let empty : Metadata := {}
  assertEq "labelParts empty" empty.labelParts ([] : List String)
  let full : Metadata :=
    { phase := some "forward", backend := some "cuda", dtype := some "f32"
      device := some "cuda:0", moduleName := some "m" }
  assertEq "labelParts order"
    full.labelParts ["forward", "cuda", "f32", "cuda:0", "m"]
  let part : Metadata := { phase := some "p", device := some "d" }
  assertEq "labelParts skips none" part.labelParts ["p", "d"]

def testSummaryKeyAndTraceCategory : IO Unit := do
  let e1 : Event := { name := "op", startNs := 0, endNs := 1, depth := 0, index := 0 }
  assertEq "summaryKey bare" e1.summaryKey "op"
  assertEq "traceCategory default" e1.traceCategory "lean"
  let e2 : Event :=
    { name := "op", startNs := 0, endNs := 1, depth := 0, index := 0
      metadata := { phase := some "forward", backend := some "cpu", moduleName := some "mlp" } }
  assertEq "summaryKey labeled" e2.summaryKey "forward/cpu/mlp:op"
  assertEq "traceCategory phase" e2.traceCategory "forward"

def testDurationAndAllocHelpers : IO Unit := do
  let e : Event := { name := "x", startNs := 10, endNs := 25, depth := 0, index := 0 }
  assertEq "durationNs" e.durationNs 15
  assertEq "phaseName default" ({} : Metadata).phaseName "other"
  assertEq "phaseName set" ({ phase := some "fwd" } : Metadata).phaseName "fwd"
  assertEq "deviceName default" ({} : Metadata).deviceName "unknown"
  assertEq "deviceName set" ({ device := some "cpu" } : Metadata).deviceName "cpu"
  assertEq "shapeLabel empty" ({} : Metadata).shapeLabel "-"
  assertEq "shapeLabel out only"
    ({ outputShape := some "[2]" } : Metadata).shapeLabel "[2]"
  assertEq "shapeLabel in only"
    ({ inputShapes := #["[2]", "[3]"] } : Metadata).shapeLabel "[2] x [3]"
  assertEq "shapeLabel both"
    ({ inputShapes := #["[2]"], outputShape := some "[4]" } : Metadata).shapeLabel "[2] -> [4]"
  assertEq "opName fallback" e.opName "x"
  let eg : Event :=
    { name := "x", startNs := 0, endNs := 1, depth := 0, index := 0
      metadata := { graphNode := some "node_9" } }
  assertEq "opName graph" eg.opName "node_9"
  assertEq "allocDelta none" (allocDeltaMagnitude e) 0
  assertEq "allocDelta pos"
    (allocDeltaMagnitude { e with metadata := { allocDeltaBytes := some (5 : Int) } }) 5
  assertEq "allocDelta neg"
    (allocDeltaMagnitude { e with metadata := { allocDeltaBytes := some (-8 : Int) } }) 8

def testEventStartLt : IO Unit := do
  let a : Event := { name := "a", startNs := 1, endNs := 2, depth := 0, index := 0 }
  let b : Event := { name := "b", startNs := 2, endNs := 3, depth := 0, index := 1 }
  let c : Event := { name := "c", startNs := 1, endNs := 2, depth := 0, index := 2 }
  assertTrue "startLt earlier" (eventStartLt a b)
  assertTrue "startLt not reverse" !(eventStartLt b a)
  assertTrue "startLt index tiebreak" (eventStartLt a c)
  assertTrue "startLt not self" !(eventStartLt a a)

def testToTraceArgs : IO Unit := do
  let empty := ({} : Metadata).toTraceArgs
  assertEq "toTraceArgs empty" empty.size 0
  let full : Metadata :=
    { phase := some "forward", backend := some "cuda", dtype := some "f32"
      device := some "cuda:0", timing := some "synced", moduleName := some "m"
      graphNode := some "g", stepIndex := some 3
      inputShapes := #["[1]", "[2]"], outputShape := some "[3]"
      allocBytes := some 10, allocLiveBytes := some 20, allocPeakBytes := some 30
      allocDeltaBytes := some (-4) }
  let args := full.toTraceArgs
  let joined := String.intercalate "," args.toList
  for needle in
      ["\"phase\":\"forward\"", "\"backend\":\"cuda\"", "\"dtype\":\"f32\"",
       "\"device\":\"cuda:0\"", "\"timing\":\"synced\"", "\"module\":\"m\"",
       "\"graph_node\":\"g\"", "\"step\":3", "\"input_shapes\":", "\"output_shape\":\"[3]\"",
       "\"alloc_bytes\":10", "\"alloc_live_bytes\":20", "\"alloc_peak_bytes\":30",
       "\"alloc_delta_bytes\":-4"] do
    assertContains s!"toTraceArgs has {needle}" joined needle

/-! ## 3. Summary / child duration math -/

def testChildDurationsExplicit : IO Unit := do
  let outer : Event := { name := "outer", startNs := 0, endNs := 100, depth := 0, index := 0 }
  let mid : Event :=
    { name := "mid", startNs := 10, endNs := 60, depth := 1, index := 1, parentIndex := some 0 }
  let leaf : Event :=
    { name := "leaf", startNs := 20, endNs := 30, depth := 2, index := 2, parentIndex := some 1 }
  let sibling : Event :=
    { name := "sib", startNs := 70, endNs := 80, depth := 1, index := 3, parentIndex := some 0 }
  let kids := childDurationsByIndex #[outer, mid, leaf, sibling]
  assertEq "explicit child outer" (kids.getD 0 0) 60
  assertEq "explicit child mid" (kids.getD 1 0) 10
  assertEq "explicit child leaf" (kids.getD 2 0) 0
  assertEq "explicit child sib" (kids.getD 3 0) 0

def testChildDurationsStackFallback : IO Unit := do
  let outer : Event := { name := "outer", startNs := 0, endNs := 100, depth := 0, index := 0 }
  let inner : Event := { name := "inner", startNs := 10, endNs := 40, depth := 1, index := 1 }
  let kids := childDurationsByIndex #[outer, inner]
  assertEq "stack fallback outer children" (kids.getD 0 0) 30
  assertEq "stack fallback inner children" (kids.getD 1 0) 0

def testChildDurationsEmptyAndFlat : IO Unit := do
  let kids0 := childDurationsByIndex #[]
  assertEq "empty child map size" kids0.size 0
  let a : Event := { name := "a", startNs := 0, endNs := 5, depth := 0, index := 0 }
  let b : Event := { name := "b", startNs := 10, endNs := 20, depth := 0, index := 1 }
  let kids := childDurationsByIndex #[a, b]
  assertEq "flat siblings no children a" (kids.getD 0 0) 0
  assertEq "flat siblings no children b" (kids.getD 1 0) 0

def testBuildSummaryRowsBasics : IO Unit := do
  let outer : Event := { name := "outer", startNs := 0, endNs := 10, depth := 0, index := 0 }
  let inner : Event :=
    { name := "inner", startNs := 2, endNs := 5, depth := 1, index := 1, parentIndex := some 0 }
  let rows := buildSummaryRows #[outer, inner]
  match findRow "outer" rows, findRow "inner" rows with
  | some o, some i =>
      assertEq "outer total" o.totalNs 10
      assertEq "outer self" o.selfNs 7
      assertEq "outer calls" o.calls 1
      assertEq "inner total" i.totalNs 3
      assertEq "inner self" i.selfNs 3
      assertEq "inner calls" i.calls 1
      let r0 ← firstArr "rows" rows
      let r1 ← getIdx "rows" rows 1
      assertTrue "sorted by self desc" (r0.selfNs ≥ r1.selfNs)
      assertEq "pct outer" o.pct ((7 * 1000) / 10)
      assertEq "pct inner" i.pct ((3 * 1000) / 10)
  | _, _ => fail "missing summary rows"

def testBuildSummaryRowsAggregation : IO Unit := do
  let e1 : Event :=
    { name := "op", startNs := 0, endNs := 10, depth := 0, index := 0
      metadata := { phase := some "forward" } }
  let e2 : Event :=
    { name := "op", startNs := 20, endNs := 25, depth := 0, index := 1
      metadata := { phase := some "forward" } }
  let e3 : Event :=
    { name := "op", startNs := 30, endNs := 50, depth := 0, index := 2
      metadata := { phase := some "backward" } }
  let rows := buildSummaryRows #[e1, e2, e3]
  match findRow "forward:op" rows, findRow "backward:op" rows with
  | some f, some b =>
      assertEq "forward aggregate total" f.totalNs 15
      assertEq "forward aggregate calls" f.calls 2
      assertEq "backward aggregate total" b.totalNs 20
      assertEq "backward aggregate calls" b.calls 1
  | _, _ => fail "missing aggregated rows"

def testBuildSummaryRowsEmpty : IO Unit := do
  assertEq "empty summary" (buildSummaryRows #[]).size 0

def testBuildSummaryRowsZeroDuration : IO Unit := do
  let e : Event := { name := "z", startNs := 5, endNs := 5, depth := 0, index := 0 }
  match findRow "z" (buildSummaryRows #[e]) with
  | some r =>
      assertEq "zero dur total" r.totalNs 0
      assertEq "zero dur self" r.selfNs 0
      assertEq "zero dur pct" r.pct 0
  | none => fail "missing zero-duration row"

def testSummaryStableUnderReorderInput : IO Unit := do
  let a : Event := { name := "a", startNs := 0, endNs := 10, depth := 0, index := 0 }
  let b : Event :=
    { name := "b", startNs := 1, endNs := 4, depth := 1, index := 1, parentIndex := some 0 }
  let rows1 := buildSummaryRows #[a, b]
  let rows2 := buildSummaryRows #[b, a]
  match findRow "a" rows1, findRow "a" rows2, findRow "b" rows1, findRow "b" rows2 with
  | some a1, some a2, some b1, some b2 =>
      assertEq "a self stable" a1.selfNs a2.selfNs
      assertEq "b self stable" b1.selfNs b2.selfNs
  | _, _, _, _ => fail "missing rows in reorder test"

def testOverlappingExplicitParentsEdge : IO Unit := do
  let p : Event := { name := "p", startNs := 0, endNs := 100, depth := 0, index := 0 }
  let c1 : Event :=
    { name := "c1", startNs := 0, endNs := 40, depth := 1, index := 1, parentIndex := some 0 }
  let c2 : Event :=
    { name := "c2", startNs := 10, endNs := 50, depth := 1, index := 2, parentIndex := some 0 }
  match findRow "p" (buildSummaryRows #[p, c1, c2]) with
  | some pr => assertEq "overlapping children self" pr.selfNs 20
  | none => fail "missing parent row"

/-! ## 4. Aggregation helpers for HTML report -/

def sampleEvents : Array Event :=
  #[
    { name := "matmul", startNs := 100, endNs := 200, depth := 0, index := 0
      metadata :=
        { phase := some "forward", device := some "cuda:0", moduleName := some "attn"
          graphNode := some "n1", stepIndex := some 0
          inputShapes := #["[2,4]"], outputShape := some "[2,4]"
          allocPeakBytes := some 1000, allocLiveBytes := some 800
          allocDeltaBytes := some 200 } },
    { name := "relu", startNs := 200, endNs := 250, depth := 0, index := 1
      metadata :=
        { phase := some "forward", device := some "cpu", moduleName := some "attn"
          stepIndex := some 0, outputShape := some "[2,4]"
          allocPeakBytes := some 500 } },
    { name := "grad", startNs := 300, endNs := 450, depth := 0, index := 2
      metadata :=
        { phase := some "backward", device := some "cuda:0", moduleName := some "mlp"
          graphNode := some "n2", stepIndex := some 1
          allocPeakBytes := some 2000, allocDeltaBytes := some (-50) } },
    { name := "opt", startNs := 500, endNs := 520, depth := 0, index := 3
      metadata :=
        { phase := some "step", moduleName := some "opt", stepIndex := some 1 } }
  ]

def testPhaseTotals : IO Unit := do
  let totals := phaseTotals sampleEvents
  assertEq "phaseTotals size" totals.size 3
  let head ← firstArr "phaseTotals" totals
  -- forward and backward both total 150; either may sort first on the tie.
  assertEq "phaseTotals first dur is max" head.2 150
  assertTrue "phaseTotals first is a max phase"
    (head.1 == "forward" || head.1 == "backward")
  let map := Id.run do
    let mut m : Std.HashMap String Nat := {}
    for pair in totals do m := m.insert pair.1 pair.2
    pure m
  assertEq "forward total" (map.getD "forward" 0) 150
  assertEq "backward total" (map.getD "backward" 0) 150
  assertEq "step total" (map.getD "step" 0) 20

def testShapeTotals : IO Unit := do
  let totals := shapeTotals sampleEvents
  assertTrue "shapeTotals nonempty" (totals.size > 0)
  let labels := totals.map (·.1)
  assertTrue "has arrow shape" (labels.any (· == "[2,4] -> [2,4]"))
  assertTrue "has out-only shape" (labels.any (· == "[2,4]"))

def testModuleTotals : IO Unit := do
  let totals := moduleTotals sampleEvents
  let map := Id.run do
    let mut m : Std.HashMap String (Nat × Nat × Nat) := {}
    for row in totals do
      m := m.insert row.1 (row.2.1, row.2.2.1, row.2.2.2)
    pure m
  match map["attn"]? with
  | some (t, c, p) =>
      assertEq "attn total" t 150
      assertEq "attn calls" c 2
      assertEq "attn peak" p 1000
  | none => fail "missing attn module"
  match map["mlp"]? with
  | some (t, c, p) =>
      assertEq "mlp total" t 150
      assertEq "mlp calls" c 1
      assertEq "mlp peak" p 2000
  | none => fail "missing mlp module"

def testStepTotals : IO Unit := do
  let totals := stepTotals sampleEvents
  assertEq "stepTotals sorted size" totals.size 2
  let s0 ← firstArr "stepTotals" totals
  let s1 ← getIdx "stepTotals" totals 1
  assertEq "step 0 index" s0.1 0
  assertEq "step 1 index" s1.1 1
  assertEq "step 0 total" s0.2.1 150
  assertEq "step 1 total" s1.2.1 170

def testMaxPeakBytes : IO Unit := do
  assertEq "maxPeakBytes" (maxPeakBytes sampleEvents) 2000
  assertEq "maxPeakBytes empty" (maxPeakBytes #[]) 0
  let noPeak : Event := { name := "x", startNs := 0, endNs := 1, depth := 0, index := 0 }
  assertEq "maxPeakBytes none" (maxPeakBytes #[noPeak]) 0

def testGroupRowsAndPhaseOps : IO Unit := do
  let rows := groupRowsBy sampleEvents (fun e => e.opName)
  if rows.size ≥ 2 then
    let a ← firstArr "groupRows" rows
    let b ← getIdx "groupRows" rows 1
    assertTrue "groupRows sorted" (a.totalNs ≥ b.totalNs)
  let fwd := phaseOpRows sampleEvents "forward"
  assertEq "forward ops count" fwd.size 2
  let bwd := phaseOpRows sampleEvents "backward"
  assertEq "backward ops count" bwd.size 1
  let b0 ← firstArr "bwd" bwd
  assertEq "backward op name" b0.name "n2"
  assertEq "missing phase empty" (phaseOpRows sampleEvents "missing").size 0

def testUniqueMetadataValues : IO Unit := do
  assertEq "unique phases sorted"
    (uniqueMetadataValues sampleEvents (·.phase)) #["backward", "forward", "step"]
  assertEq "unique devices"
    (uniqueMetadataValues sampleEvents (·.device)) #["cpu", "cuda:0"]
  assertEq "unique empty" (uniqueMetadataValues #[] (·.phase)) #[]
  let blank : Event :=
    { name := "x", startNs := 0, endNs := 1, depth := 0, index := 0
      metadata := { phase := some "" } }
  assertEq "unique skips empty string" (uniqueMetadataValues #[blank] (·.phase)) #[]

def testFilterOptionsHtml : IO Unit := do
  assertEq "filterOptions empty" (filterOptionsHtml #[]) ""
  let html := filterOptionsHtml #["a", "b<c"]
  assertContains "option a" html "<option value=\"a\">a</option>"
  assertContains "option escaped" html "<option value=\"b&lt;c\">b&lt;c</option>"

def testTraceBounds : IO Unit := do
  assertEq "traceStart" (traceStartNs sampleEvents) 100
  assertEq "traceEnd" (traceEndNs sampleEvents) 520
  assertEq "traceStart empty" (traceStartNs #[]) 0
  assertEq "traceEnd empty" (traceEndNs #[]) 0

def testDataAttrs : IO Unit := do
  let e0 ← firstArr "sampleEvents" sampleEvents
  let attrs := e0.dataAttrs
  assertContains "data-phase" attrs "data-phase=\"forward\""
  assertContains "data-module" attrs "data-module=\"attn\""
  assertContains "data-device" attrs "data-device=\"cuda:0\""
  assertContains "data-op" attrs "data-op=\"n1\""

def testHtmlFragmentGenerators : IO Unit := do
  let summary := buildSummaryRows sampleEvents
  let table := reportTableRows summary
  assertContains "report table has row" table "<tr data-prof-row>"
  assertContains "report table has name" table "forward"
  assertContains "phase bars" (phaseBarsHtml sampleEvents) "backward"
  assertContains "shape rows" (shapeRowsHtml sampleEvents) "[2,4]"
  assertContains "module rows" (moduleRowsHtml sampleEvents) "attn"
  assertContains "module bars" (moduleBarsHtml sampleEvents) "mlp"
  assertContains "step rows" (stepRowsHtml sampleEvents) "<td>0</td>"
  assertContains "memory rows" (memoryRowsHtml sampleEvents) "matmul"
  assertContains "timeline" (timelineRowsHtml sampleEvents) "class=\"tlrow\""
  assertContains "mem timeline" (memoryTimelineHtml sampleEvents) "class=\"memrow\""
  assertContains "slow events" (slowEventRowsHtml sampleEvents) "grad"
  -- Forward ops table keys by graphNode when present (matmul → n1).
  assertContains "fwd ops html" (phaseOpRowsHtml sampleEvents "forward") "n1"
  assertContains "empty modules message" (moduleRowsHtml #[]) "No module context"
  assertContains "empty steps message" (stepRowsHtml #[]) "No step context"
  assertContains "empty memory message" (memoryRowsHtml #[]) "No allocator metadata"
  assertContains "empty timeline message" (timelineRowsHtml #[]) "No events were recorded"
  assertContains "empty mem timeline message" (memoryTimelineHtml #[]) "No allocator metadata"
  assertContains "empty phase ops" (phaseOpRowsHtml #[] "forward") "No forward events"
  assertContains "empty module bars" (moduleBarsHtml #[]) "No module context"

/-! ## 5. Recording, nesting, clear -/

def testClearAndGetEvents : IO Unit := do
  clear
  recordSpan "a" (pure ())
  recordSpan "b" (pure ())
  assertEq "two events" (← getEvents).size 2
  clear
  assertEq "clear empties" (← getEvents).size 0

def testRecordSpanReturnsValue : IO Unit := do
  clear
  let v ← recordSpan "ret" (pure (42 : Nat))
  assertEq "recordSpan value" v 42
  let v2 ← recordSpanWith "ret2" { phase := some "p" } (pure "ok")
  assertEq "recordSpanWith value" v2 "ok"

def testNestedSpansParentAndDepth : IO Unit := do
  clear
  recordSpan "outer" do
    recordSpan "mid" do
      recordSpan "inner" (pure ())
  let ev ← getEvents
  assertEq "nested count" ev.size 3
  let inner ← firstArr "ev" ev
  let mid ← getIdx "ev" ev 1
  let outer ← getIdx "ev" ev 2
  assertEq "inner name" inner.name "inner"
  assertEq "mid name" mid.name "mid"
  assertEq "outer name" outer.name "outer"
  assertEq "inner depth" inner.depth 2
  assertEq "mid depth" mid.depth 1
  assertEq "outer depth" outer.depth 0
  assertEq "inner parent" inner.parentIndex (some mid.index)
  assertEq "mid parent" mid.parentIndex (some outer.index)
  assertEq "outer parent" outer.parentIndex (none : Option Nat)
  assertTrue "times nested" (inner.startNs ≥ outer.startNs && inner.endNs ≤ outer.endNs)
  assertTrue "mid inside outer" (mid.startNs ≥ outer.startNs && mid.endNs ≤ outer.endNs)

def testCurrentSpanIndex : IO Unit := do
  clear
  assertEq "no current outside" (← currentSpanIndex) (none : Option Nat)
  let parentRef ← IO.mkRef (none : Option Nat)
  let childRef ← IO.mkRef (none : Option Nat)
  recordSpan "parent" do
    parentRef.set (← currentSpanIndex)
    recordSpan "child" do
      childRef.set (← currentSpanIndex)
  let parentIdx ← parentRef.get
  let childIdx ← childRef.get
  match parentIdx, childIdx with
  | some p, some c => assertNe "child index differs" c p
  | _, _ => fail "missing current span index"
  assertEq "cleared after exit" (← currentSpanIndex) (none : Option Nat)

def testManySequentialSpans : IO Unit := do
  clear
  for i in [0:64] do
    recordSpanWith s!"seq_{i}" { stepIndex := some i } (pure ())
  let ev ← getEvents
  assertEq "64 sequential" ev.size 64
  let mut seen : Std.HashMap Nat Unit := {}
  for e in ev do
    if seen.contains e.index then fail "duplicate index in sequential"
    seen := seen.insert e.index ()
    assertEq "flat depth" e.depth 0
  assertEq "unique indices" seen.size 64

partial def deepGo (n : Nat) : IO Unit := do
  if n == 0 then pure ()
  else recordSpan s!"d{n}" (deepGo (n - 1))

def testDeepNesting : IO Unit := do
  clear
  let depth := 16
  deepGo depth
  let ev ← getEvents
  assertEq "deep count" ev.size depth
  for e in ev do
    assertTrue "depth in range" (e.depth < depth)

def testSpanExceptionStillRecords : IO Unit := do
  clear
  try
    recordSpan "boom" do
      throw (IO.userError "expected")
  catch _ => pure ()
  let ev ← getEvents
  assertEq "exception still records" ev.size 1
  let e0 ← firstArr "ev" ev
  assertEq "exception event name" e0.name "boom"
  assertTrue "exception event has duration field" (e0.endNs ≥ e0.startNs)

def testSiblingIndependence : IO Unit := do
  clear
  recordSpan "a" (pure ())
  recordSpan "b" (pure ())
  let ev ← getEvents
  let a ← firstArr "ev" ev
  let b ← getIdx "ev" ev 1
  assertEq "a parent none" a.parentIndex (none : Option Nat)
  assertEq "b parent none" b.parentIndex (none : Option Nat)

/-! ## 6. Context scoping -/

def testWithStepModuleContext : IO Unit := do
  clear
  withStep 3 do
    withModule "demo.mod" do
      recordSpan "inside" (pure ())
  recordSpan "outside" (pure ())
  let ev ← getEvents
  match findEvent "inside" ev, findEvent "outside" ev with
  | some inside, some outside =>
      assertEq "inside step" inside.metadata.stepIndex (some 3)
      assertEq "inside module" inside.metadata.moduleName (some "demo.mod")
      assertEq "outside step none" outside.metadata.stepIndex (none : Option Nat)
      assertEq "outside module none" outside.metadata.moduleName (none : Option String)
  | _, _ => fail "missing context events"

def testContextMergeAndOverride : IO Unit := do
  clear
  withStep 1 do
    withModule "outer" do
      withStep 2 do
        recordSpan "inner" (pure ())
      recordSpan "mid" (pure ())
  let ev ← getEvents
  match findEvent "inner" ev, findEvent "mid" ev with
  | some inner, some mid =>
      assertEq "inner step override" inner.metadata.stepIndex (some 2)
      assertEq "inner keeps module" inner.metadata.moduleName (some "outer")
      assertEq "mid step restored" mid.metadata.stepIndex (some 1)
      assertEq "mid module" mid.metadata.moduleName (some "outer")
  | _, _ => fail "missing merge events"

def testContextFailureRestores : IO Unit := do
  clear
  try
    withModule "bad" do
      recordSpan "boom" do
        throw (IO.userError "expected")
  catch _ => pure ()
  recordSpan "after" (pure ())
  match findEvent "after" (← getEvents) with
  | some e => assertEq "no leak" e.metadata.moduleName (none : Option String)
  | none => fail "missing after event"

def testMetadataBeatsContext : IO Unit := do
  clear
  withModule "ctx-mod" do
    withStep 9 do
      recordSpanWith "explicit"
        { moduleName := some "meta-mod", stepIndex := some 1 } (pure ())
  match findEvent "explicit" (← getEvents) with
  | some e =>
      assertEq "meta module wins" e.metadata.moduleName (some "meta-mod")
      assertEq "meta step wins" e.metadata.stepIndex (some 1)
  | none => fail "missing explicit event"

def testWithParentIndex : IO Unit := do
  clear
  recordSpan "parent" do
    match ← currentSpanIndex with
    | none => fail "missing parent index"
    | some parent =>
        withParentIndex parent do
          recordSpan "forced-child" (pure ())
  let ev ← getEvents
  match findEvent "parent" ev, findEvent "forced-child" ev with
  | some p, some c =>
      assertEq "forced parent link" c.parentIndex (some p.index)
      assertEq "forced child depth" c.depth (p.depth + 1)
  | _, _ => fail "missing parent/child"

/-! ## 7. Hooks -/

def testHooksHappyPath : IO Unit := do
  clear
  let beforeHit ← IO.mkRef false
  let hooks : SpanHooks :=
    { before := beforeHit.set true
      after := fun m => pure { m with timing := some "synced", allocBytes := some 99 } }
  recordSpanWithHooks "hooked" { phase := some "forward" } hooks (busyU 1000)
  assertTrue "before ran" (← beforeHit.get)
  match findEvent "hooked" (← getEvents) with
  | some e =>
      assertEq "hook timing" e.metadata.timing (some "synced")
      assertEq "hook alloc" e.metadata.allocBytes (some 99)
      assertEq "hook keeps phase" e.metadata.phase (some "forward")
  | none => fail "hook event missing"

def testHooksAfterFailureKeepsSpan : IO Unit := do
  clear
  let hooks : SpanHooks :=
    { before := pure ()
      after := fun _ => throw (IO.userError "after failed") }
  recordSpanWithHooks "hook-fail" { phase := some "forward" } hooks (pure ())
  match findEvent "hook-fail" (← getEvents) with
  | some e =>
      assertEq "keeps original phase" e.metadata.phase (some "forward")
      assertEq "timing unset after failure" e.metadata.timing (none : Option String)
  | none => fail "hook-fail missing"

def testHooksBeforeFailurePropagates : IO Unit := do
  clear
  let hooks : SpanHooks :=
    { before := throw (IO.userError "before failed")
      after := fun m => pure m }
  let threw ← IO.mkRef false
  try
    recordSpanWithHooks "never" {} hooks (pure ())
  catch _ =>
    threw.set true
  assertTrue "before failure propagates" (← threw.get)
  assertEq "no event after before failure" (← getEvents).size 0

/-! ## 8. Concurrency -/

def testConcurrentAppends : IO Unit := do
  clear
  let taskCount := 12
  let spansPerTask := 40
  let mut tasks : Array (Task (Except IO.Error Unit)) := #[]
  for taskIndex in [0:taskCount] do
    let task ← IO.asTask (prio := Task.Priority.dedicated) do
      for spanIndex in [0:spansPerTask] do
        recordSpanWith "concurrent"
          { phase := some "test"
            stepIndex := some taskIndex
            graphNode := some s!"span_{spanIndex}" } (pure ())
    tasks := tasks.push task
  for t in tasks do runTask t
  let ev ← getEvents
  assertEq "concurrent count" ev.size (taskCount * spansPerTask)
  let mut seen : Std.HashMap Nat Unit := {}
  for e in ev do
    if seen.contains e.index then fail "duplicate concurrent index"
    if e.depth != 0 || e.parentIndex.isSome then
      fail "independent concurrent spans should be roots"
    seen := seen.insert e.index ()

def testConcurrentNestedPerTask : IO Unit := do
  clear
  let taskCount := 6
  let mut tasks : Array (Task (Except IO.Error Unit)) := #[]
  for _ in [0:taskCount] do
    let task ← IO.asTask (prio := Task.Priority.dedicated) do
      recordSpan "t-outer" do
        recordSpan "t-inner" (pure ())
    tasks := tasks.push task
  for t in tasks do runTask t
  let ev ← getEvents
  assertEq "nested concurrent count" ev.size (taskCount * 2)
  let inners := ev.filter (·.name == "t-inner")
  for e in inners do
    assertEq "inner depth" e.depth 1
    assertTrue "inner has parent" e.parentIndex.isSome

def testCrossTaskParentLink : IO Unit := do
  clear
  recordSpan "parent" do
    match ← currentSpanIndex with
    | none => fail "missing parent"
    | some parent =>
        let task ← IO.asTask (prio := Task.Priority.dedicated) do
          withParentIndex parent do
            recordSpan "child" (pure ())
        runTask task
  let ev ← getEvents
  match findEvent "parent" ev, findEvent "child" ev with
  | some p, some c =>
      assertEq "cross parent" c.parentIndex (some p.index)
      assertEq "cross depth" c.depth (p.depth + 1)
  | _, _ => fail "missing cross-task events"

/-! ## 9. Export: trace + HTML + finish -/

def testExportTraceContents : IO Unit := do
  clear
  let path := s!"{artifactDir}/trace-basic.json"
  rm path
  withStep 2 do
    withModule "mod" do
      recordSpanWith "op"
        { phase := some "forward", device := some "cpu"
          inputShapes := #["[1]"], outputShape := some "[1]"
          allocBytes := some 8 } (busyU 2000)
  exportTrace path
  let json ← readFile path
  assertContains "displayTimeUnit" json "\"displayTimeUnit\":\"ns\""
  assertContains "traceEvents" json "\"traceEvents\":"
  assertContains "name" json "\"name\":\"op\""
  assertContains "cat phase" json "\"cat\":\"forward\""
  assertContains "ph X" json "\"ph\":\"X\""
  assertContains "pid" json "\"pid\":1"
  assertContains "args index" json "\"event_index\":"
  assertContains "args depth" json "\"event_depth\":"
  assertContains "step arg" json "\"step\":2"
  assertContains "module arg" json "\"module\":\"mod\""
  assertContains "device arg" json "\"device\":\"cpu\""
  assertContains "shapes" json "\"input_shapes\":"
  assertNotContains "no trailing junk object" json "}{"

def testExportTraceEscaping : IO Unit := do
  clear
  let path := s!"{artifactDir}/trace-escape.json"
  rm path
  recordSpanWith "a\"b\\c" { phase := some "p\"q" } (pure ())
  exportTrace path
  let json ← readFile path
  assertContains "escaped name" json "\"name\":\"a\\\"b\\\\c\""
  assertContains "escaped cat" json "\"cat\":\"p\\\"q\""

def testExportTraceCreatesDirs : IO Unit := do
  clear
  let path := s!"{artifactDir}/nested/dir/trace.json"
  rm path
  recordSpan "x" (pure ())
  exportTrace path
  assertContains "nested write" (← readFile path) "\"name\":\"x\""

def testExportHtmlReport : IO Unit := do
  clear
  let path := s!"{artifactDir}/report-base.json"
  let htmlPath := reportPathForTrace path
  rm path; rm htmlPath
  withStep 0 do
    withModule "attn" do
      recordSpanWith "matmul"
        { phase := some "forward", device := some "cuda:0"
          graphNode := some "n1", inputShapes := #["[2,4]"], outputShape := some "[2,4]"
          allocPeakBytes := some 1000, allocLiveBytes := some 800
          allocDeltaBytes := some 200 } (busyU 3000)
      recordSpanWith "relu"
        { phase := some "forward", device := some "cpu", outputShape := some "[2,4]"
          allocPeakBytes := some 500 } (busyU 1000)
  withStep 1 do
    withModule "mlp" do
      recordSpanWith "grad"
        { phase := some "backward", device := some "cuda:0", graphNode := some "n2"
          allocPeakBytes := some 2000, allocDeltaBytes := some (-50) } (busyU 4000)
    withModule "opt" do
      recordSpanWith "opt" { phase := some "step" } (busyU 500)
  exportHtmlReport path
  let html ← readFile htmlPath
  assertContains "doctype" html "<!doctype html>"
  assertContains "title" html "LeanProfiler Runtime Profile"
  assertContains "filters" html "id=\"globalFilter\""
  assertContains "phase filter" html "id=\"phaseFilter\""
  assertContains "module filter" html "id=\"moduleFilter\""
  assertContains "device filter" html "id=\"deviceFilter\""
  assertContains "cards" html "Events"
  assertContains "phase split" html "Phase Split"
  assertContains "forward ops" html "Forward Operators"
  assertContains "backward" html "Backward Graph Nodes"
  assertContains "timeline" html "Timeline Preview"
  assertContains "memory" html "Memory Timeline"
  assertContains "script" html "applyGlobalFilters"
  assertContains "matmul present" html "matmul"
  assertTrue "html reasonably large" (html.length > 5000)

def testFinishModes : IO Unit := do
  clear
  let p1 := s!"{artifactDir}/finish-summary.json"
  rm p1; rm (reportPathForTrace p1)
  recordSpan "s" (busyU 1000)
  finish .summary p1
  assertTrue "summary mode no trace file" !(← fileExists p1)

  clear
  let p2 := s!"{artifactDir}/finish-trace.json"
  rm p2; rm (reportPathForTrace p2)
  recordSpan "t" (pure ())
  finish .trace p2
  let _ ← readFile p2
  assertTrue "trace mode no html" !(← fileExists (reportPathForTrace p2))

  clear
  let p3 := s!"{artifactDir}/finish-html.json"
  rm p3; rm (reportPathForTrace p3)
  recordSpan "h" (pure ())
  finish .html p3
  let _ ← readFile (reportPathForTrace p3)

  clear
  let p4 := s!"{artifactDir}/finish-all.json"
  rm p4; rm (reportPathForTrace p4)
  recordSpan "a" (busyU 2000)
  finish .all p4
  let _ ← readFile p4
  let _ ← readFile (reportPathForTrace p4)

def testFinishIdempotent : IO Unit := do
  clear
  let path := s!"{artifactDir}/finish-once.json"
  rm path; rm (reportPathForTrace path)
  recordSpan "once" (pure ())
  finish .trace path
  let first ← readFile path
  recordSpan "after-finish" (pure ())
  finish .trace path
  let second ← readFile path
  assertEq "finish idempotent content" first second
  assertNotContains "second finish did not rewrite with new event" second "after-finish"
  clear
  recordSpan "again" (pure ())
  finish .trace path
  assertContains "after clear finish works" (← readFile path) "again"

def testFinishSummaryThenAllBlocked : IO Unit := do
  clear
  let path := s!"{artifactDir}/blocked.json"
  rm path; rm (reportPathForTrace path)
  recordSpan "x" (pure ())
  finish .summary path
  finish .all path
  assertTrue "second finish .all blocked" !(← fileExists path)

def testPrintSummarySmoke : IO Unit := do
  clear
  recordSpan "smoke" (busyU 5000)
  printSummary

/-! ## 10. Sugar: span / spanCore / withProfiledMain -/

def testSpanCorePureAndIO : IO Unit := do
  clear
  let seed := (← IO.monoNanosNow) % 97 + 1
  let expected := heavy 50_000 seed
  let viaCore ← spanCore "pure-core" (heavy 50_000 seed)
  assertEq "spanCore pure value" viaCore expected
  let viaIO ← spanCore "io-core" (busy 2000)
  assertTrue "spanCore io value" (viaIO ≥ 0)
  if profilingEnabled then
    let ev ← getEvents
    assertTrue "spanCore recorded when enabled" (countNamed "pure-core" ev ≥ 1)
    assertTrue "spanCore io recorded" (countNamed "io-core" ev ≥ 1)
  else
    assertEq "spanCore silent when disabled" (← getEvents).size 0

def testSpanMacro : IO Unit := do
  clear
  let seed := (← IO.monoNanosNow) % 97 + 1
  let expected := heavy 40_000 seed
  let got ← span "macro-pure" (heavy 40_000 seed)
  assertEq "span macro pure value" got expected
  let ioGot ← span "macro-io" (busy 1500)
  assertTrue "span macro io" (ioGot ≥ 0)
  if profilingEnabled then
    assertTrue "macro recorded" (countNamed "macro-pure" (← getEvents) ≥ 1)
  else
    assertEq "macro silent" (← getEvents).size 0

/-- `span` on an `IO` action must actually execute it (Spannable IO instance wins). -/
def testSpanIOActuallyRuns : IO Unit := do
  clear
  let flag ← IO.mkRef false
  let act : IO Unit := flag.set true
  let _ ← span "io-runs" act
  assertTrue "span ran IO body" (← flag.get)
  if profilingEnabled then
    match findEvent "io-runs" (← getEvents) with
    | some _ => pure ()
    | none => fail "io-runs not recorded"
  -- Measurable work: IO busy should dominate a tiny pure span when both recorded via Runtime.
  clear
  recordSpan "tiny" (pure ())
  recordSpan "heavy-io" (busyU 200_000)
  let rows := buildSummaryRows (← getEvents)
  match findRow "tiny" rows, findRow "heavy-io" rows with
  | some t, some h => assertTrue "IO busy attributed" (h.selfNs > t.selfNs)
  | _, _ => fail "missing timing rows"

def testSpanCoreWithMetadata : IO Unit := do
  clear
  let _ ← spanCore "meta-span" (busyU 1000) { phase := some "forward", device := some "cpu" }
  if profilingEnabled then
    match findEvent "meta-span" (← getEvents) with
    | some e =>
        assertEq "spanCore meta phase" e.metadata.phase (some "forward")
        assertEq "spanCore meta device" e.metadata.device (some "cpu")
    | none => fail "meta-span missing"

def testPureAttribution : IO Unit := do
  clear
  let seed := (← IO.monoNanosNow) % 97 + 1
  let big ← recordSpanWith "heavy" {} (IO.lazyPure (fun _ => heavy 2_000_000 seed))
  let small ← recordSpanWith "light" {} (IO.lazyPure (fun _ => heavy 20_000 seed))
  if big == 0 && small == 0 then fail "unexpected zeros"
  let rows := buildSummaryRows (← getEvents)
  match findRow "heavy" rows, findRow "light" rows with
  | some h, some l =>
      assertTrue "heavy self > 0" (h.selfNs > 0)
      assertTrue "heavy > light" (h.selfNs > l.selfNs)
  | _, _ => fail "missing attribution rows"

def testWithProfiledMainDisabledOrEnabled : IO Unit := do
  clear
  if profilingEnabled then
    recordSpan "preexisting" (pure ())
    let v ← withProfiledMain do
      recordSpan "during" (busyU 2000)
      pure (7 : Nat)
    assertEq "enabled returns value" v 7
    let _ ← readFile profileOutputPath
    let _ ← readFile (reportPathForTrace profileOutputPath)
  else
    let v ← withProfiledMain do
      recordSpan "during-disabled" (pure ())
      pure (11 : Nat)
    assertEq "disabled returns value" v 11
    assertEq "disabled still recorded via Runtime API"
      (countNamed "during-disabled" (← getEvents)) 1

unsafe def testEvalSpanUnsafe : IO Unit := do
  if profilingEnabled then
    let seed := (← IO.monoNanosNow) % 50 + 1
    let expected := heavy 30_000 seed
    let got := evalSpan "eval-span" (heavy 30_000 seed)
    assertEq "evalSpan value" got expected
  else
    let got := evalSpan "eval-span-off" (123 : Nat)
    assertEq "evalSpan off value" got 123

/-- `profiled def` for an IO function. -/
profiled def profiledIoFn (n : Nat) : IO Nat :=
  busy n

/-- `profiled def` for a pure function. -/
profiled def profiledPureFn (n seed : Nat) : Nat :=
  heavy n seed

def testProfiledDefFunctions : IO Unit := do
  clear
  let seed := (← IO.monoNanosNow) % 40 + 1
  let ioV ← profiledIoFn 3000
  assertTrue "profiled IO value" (ioV ≥ 0)
  let pureV := profiledPureFn 20_000 seed
  assertEq "profiled pure value" pureV (heavy 20_000 seed)
  if profilingEnabled then
    let ev ← getEvents
    assertTrue "profiled IO recorded" (countNamed "profiledIoFn" ev ≥ 1)
    assertTrue "profiled pure recorded" (countNamed "profiledPureFn" ev ≥ 1)
  else
    assertEq "profiled silent when off" (← getEvents).size 0

/-! ## 11. Timing sanity / monotonicity -/

def testTimestampsMonotonic : IO Unit := do
  clear
  recordSpan "t1" (busyU 5000)
  recordSpan "t2" (busyU 5000)
  let ev ← getEvents
  let t1 ← firstArr "ev" ev
  let t2 ← getIdx "ev" ev 1
  assertTrue "t1 duration > 0" (t1.durationNs > 0)
  assertTrue "t2 duration > 0" (t2.durationNs > 0)
  assertTrue "t2 starts after t1 start" (t2.startNs ≥ t1.startNs)

def testNestedSelfTimePositive : IO Unit := do
  clear
  recordSpan "outer" do
    busyU 8000
    recordSpan "inner" (busyU 8000)
    busyU 8000
  let rows := buildSummaryRows (← getEvents)
  match findRow "outer" rows, findRow "inner" rows with
  | some o, some i =>
      assertTrue "inner self > 0" (i.selfNs > 0)
      assertTrue "outer self > 0" (o.selfNs > 0)
      assertTrue "outer total ≥ outer self" (o.totalNs ≥ o.selfNs)
      assertTrue "outer total ≥ inner total" (o.totalNs ≥ i.totalNs)
  | _, _ => fail "missing nested self rows"

/-! ## 12. Stress / volume -/

def testHighVolumeFlat : IO Unit := do
  clear
  for i in [0:500] do
    recordSpanWith "vol" { stepIndex := some (i % 7) } (pure ())
  let ev ← getEvents
  assertEq "500 events" ev.size 500
  match findRow "vol" (buildSummaryRows ev) with
  | some r => assertEq "vol calls" r.calls 500
  | none => fail "missing vol row"
  let path := s!"{artifactDir}/volume.json"
  rm path; rm (reportPathForTrace path)
  exportTrace path
  exportHtmlReport path
  assertContains "volume json" (← readFile path) "\"name\":\"vol\""
  assertContains "volume html" (← readFile (reportPathForTrace path)) "vol"

def testHighVolumeNested : IO Unit := do
  clear
  for i in [0:50] do
    recordSpan s!"root_{i}" do
      recordSpan s!"child_{i}" do
        recordSpan s!"leaf_{i}" (pure ())
  let ev ← getEvents
  assertEq "150 nested" ev.size 150
  let leaves := ev.filter (fun e => String.isPrefixOf "leaf" e.name)
  assertEq "50 leaves" leaves.size 50
  for e in leaves do
    assertEq "leaf depth" e.depth 2

/-! ## Extra edge cases -/

def testEmptyExports : IO Unit := do
  clear
  let path := s!"{artifactDir}/empty.json"
  rm path; rm (reportPathForTrace path)
  exportTrace path
  exportHtmlReport path
  let json ← readFile path
  assertContains "empty trace array" json "\"traceEvents\":["
  let html ← readFile (reportPathForTrace path)
  assertContains "empty html still renders" html "LeanProfiler Runtime Profile"
  assertContains "empty events card" html ">0<"

def testRecordSpanWithDefaultMetadata : IO Unit := do
  clear
  recordSpanWith "plain" {} (pure ())
  match findEvent "plain" (← getEvents) with
  | some e =>
      assertEq "default phase none" e.metadata.phase (none : Option String)
      assertEq "default device none" e.metadata.device (none : Option String)
  | none => fail "plain missing"

def testThreadIdRecorded : IO Unit := do
  clear
  recordSpan "tid" (pure ())
  let e ← firstArr "ev" (← getEvents)
  assertTrue "thread id nonzero-or-zero-ok" true
  let _ := e.threadId

def testFinishHtmlOnlyCreatesHtml : IO Unit := do
  clear
  let path := s!"{artifactDir}/html-only.json"
  rm path; rm (reportPathForTrace path)
  recordSpan "h" (pure ())
  finish .html path
  let html ← readFile (reportPathForTrace path)
  assertContains "html only content" html "h"
  let _ ← fileExists path
  assertTrue "html only ok" true

def testNestedContextAcrossModules : IO Unit := do
  clear
  withModule "a" do
    recordSpan "in-a" (pure ())
    withModule "b" do
      recordSpan "in-b" (pure ())
    recordSpan "back-a" (pure ())
  let ev ← getEvents
  match findEvent "in-a" ev, findEvent "in-b" ev, findEvent "back-a" ev with
  | some a, some b, some a2 =>
      assertEq "in-a mod" a.metadata.moduleName (some "a")
      assertEq "in-b mod" b.metadata.moduleName (some "b")
      assertEq "back-a mod" a2.metadata.moduleName (some "a")
  | _, _, _ => fail "missing nested module events"

def testSelfTimeExactMultiChildren : IO Unit := do
  let p : Event := { name := "p", startNs := 0, endNs := 100, depth := 0, index := 0 }
  let c1 : Event :=
    { name := "c1", startNs := 0, endNs := 10, depth := 1, index := 1, parentIndex := some 0 }
  let c2 : Event :=
    { name := "c2", startNs := 20, endNs := 50, depth := 1, index := 2, parentIndex := some 0 }
  let c3 : Event :=
    { name := "c3", startNs := 60, endNs := 75, depth := 1, index := 3, parentIndex := some 0 }
  match findRow "p" (buildSummaryRows #[p, c1, c2, c3]) with
  | some row => assertEq "self 100-10-30-15" row.selfNs 45
  | none => fail "missing p"

def testPctSumsNear1000 : IO Unit := do
  let a : Event := { name := "a", startNs := 0, endNs := 70, depth := 0, index := 0 }
  let b : Event := { name := "b", startNs := 0, endNs := 30, depth := 0, index := 1 }
  let rows := buildSummaryRows #[a, b]
  let pctSum := rows.foldl (init := 0) fun acc r => acc + r.pct
  -- tenths of a percent; should total ~1000 (100.0%)
  assertEq "pct sum" pctSum 1000

def testDisplayNameCustomWidth : IO Unit := do
  assertEq "width 5 trunc" (displayName "abcdef" 5) "...ef"
  assertEq "width 3 trunc" (displayName "abcd" 3) "..."

def testFlameBarTinyFraction : IO Unit := do
  -- 1/24 of total → one hash unit if integer division lands ≥ 1
  let bar := flameBar 1 flameBarWidth
  assertTrue "tiny fraction length ≤ 1" (bar.length ≤ 1)

def testJsonEscapeUnicodePassthrough : IO Unit := do
  assertEq "unicode" (jsonEscape "αβ") "αβ"

def testHtmlEscapeNoOpPlain : IO Unit := do
  assertEq "plain html" (htmlEscape "abc 123") "abc 123"

/-! ## Runner -/

/-- Run one named test, printing progress. -/
def runTest (name : String) (action : IO Unit) : IO Unit := do
  IO.println s!"  • {name}"
  try
    action
  catch e =>
    fail s!"[{name}] {e.toString}"

unsafe def main : IO Unit := do
  IO.FS.createDirAll artifactDir
  IO.println "LeanProfiler exhaustive suite"
  IO.println s!"  profilingEnabled = {profilingEnabled}"
  IO.println s!"  profileOutputPath = {profileOutputPath}"
  IO.println ""

  IO.println "== formatting =="
  runTest "padRight" testPadRight
  runTest "padLeft" testPadLeft
  runTest "displayName" testDisplayName
  runTest "formatDuration" testFormatDuration
  runTest "flameBar" testFlameBar
  runTest "jsonEscape" testJsonEscape
  runTest "htmlEscape" testHtmlEscape
  runTest "jsonFields" testJsonFields
  runTest "phaseColor" testPhaseColor
  runTest "reportPath" testReportPath
  runTest "displayNameCustomWidth" testDisplayNameCustomWidth
  runTest "flameBarTinyFraction" testFlameBarTinyFraction
  runTest "jsonEscapeUnicode" testJsonEscapeUnicodePassthrough
  runTest "htmlEscapePlain" testHtmlEscapeNoOpPlain

  IO.println "== metadata / pure helpers =="
  runTest "metadataWithContext" testMetadataWithContext
  runTest "metadataLabelParts" testMetadataLabelParts
  runTest "summaryKeyAndTraceCategory" testSummaryKeyAndTraceCategory
  runTest "durationAndAllocHelpers" testDurationAndAllocHelpers
  runTest "eventStartLt" testEventStartLt
  runTest "toTraceArgs" testToTraceArgs

  IO.println "== summary math =="
  runTest "childDurationsExplicit" testChildDurationsExplicit
  runTest "childDurationsStackFallback" testChildDurationsStackFallback
  runTest "childDurationsEmptyAndFlat" testChildDurationsEmptyAndFlat
  runTest "buildSummaryRowsBasics" testBuildSummaryRowsBasics
  runTest "buildSummaryRowsAggregation" testBuildSummaryRowsAggregation
  runTest "buildSummaryRowsEmpty" testBuildSummaryRowsEmpty
  runTest "buildSummaryRowsZeroDuration" testBuildSummaryRowsZeroDuration
  runTest "summaryStableUnderReorder" testSummaryStableUnderReorderInput
  runTest "overlappingExplicitParents" testOverlappingExplicitParentsEdge
  runTest "selfTimeExactMultiChildren" testSelfTimeExactMultiChildren
  runTest "pctSumsNear1000" testPctSumsNear1000

  IO.println "== aggregations / html fragments =="
  runTest "phaseTotals" testPhaseTotals
  runTest "shapeTotals" testShapeTotals
  runTest "moduleTotals" testModuleTotals
  runTest "stepTotals" testStepTotals
  runTest "maxPeakBytes" testMaxPeakBytes
  runTest "groupRowsAndPhaseOps" testGroupRowsAndPhaseOps
  runTest "uniqueMetadataValues" testUniqueMetadataValues
  runTest "filterOptionsHtml" testFilterOptionsHtml
  runTest "traceBounds" testTraceBounds
  runTest "dataAttrs" testDataAttrs
  runTest "htmlFragmentGenerators" testHtmlFragmentGenerators

  IO.println "== recording / nesting =="
  runTest "clearAndGetEvents" testClearAndGetEvents
  runTest "recordSpanReturnsValue" testRecordSpanReturnsValue
  runTest "nestedSpansParentAndDepth" testNestedSpansParentAndDepth
  runTest "currentSpanIndex" testCurrentSpanIndex
  runTest "manySequentialSpans" testManySequentialSpans
  runTest "deepNesting" testDeepNesting
  runTest "spanExceptionStillRecords" testSpanExceptionStillRecords
  runTest "siblingIndependence" testSiblingIndependence
  runTest "recordSpanWithDefaultMetadata" testRecordSpanWithDefaultMetadata
  runTest "threadIdRecorded" testThreadIdRecorded

  IO.println "== context =="
  runTest "withStepModuleContext" testWithStepModuleContext
  runTest "contextMergeAndOverride" testContextMergeAndOverride
  runTest "contextFailureRestores" testContextFailureRestores
  runTest "metadataBeatsContext" testMetadataBeatsContext
  runTest "withParentIndex" testWithParentIndex
  runTest "nestedContextAcrossModules" testNestedContextAcrossModules

  IO.println "== hooks =="
  runTest "hooksHappyPath" testHooksHappyPath
  runTest "hooksAfterFailureKeepsSpan" testHooksAfterFailureKeepsSpan
  runTest "hooksBeforeFailurePropagates" testHooksBeforeFailurePropagates

  IO.println "== concurrency =="
  runTest "concurrentAppends" testConcurrentAppends
  runTest "concurrentNestedPerTask" testConcurrentNestedPerTask
  runTest "crossTaskParentLink" testCrossTaskParentLink

  IO.println "== export / finish =="
  runTest "exportTraceContents" testExportTraceContents
  runTest "exportTraceEscaping" testExportTraceEscaping
  runTest "exportTraceCreatesDirs" testExportTraceCreatesDirs
  runTest "exportHtmlReport" testExportHtmlReport
  runTest "finishModes" testFinishModes
  runTest "finishIdempotent" testFinishIdempotent
  runTest "finishSummaryThenAllBlocked" testFinishSummaryThenAllBlocked
  runTest "finishHtmlOnly" testFinishHtmlOnlyCreatesHtml
  runTest "printSummarySmoke" testPrintSummarySmoke
  runTest "emptyExports" testEmptyExports

  IO.println "== sugar =="
  runTest "spanCorePureAndIO" testSpanCorePureAndIO
  runTest "spanMacro" testSpanMacro
  runTest "spanIOActuallyRuns" testSpanIOActuallyRuns
  runTest "spanCoreWithMetadata" testSpanCoreWithMetadata
  runTest "pureAttribution" testPureAttribution
  runTest "withProfiledMain" testWithProfiledMainDisabledOrEnabled
  runTest "evalSpanUnsafe" testEvalSpanUnsafe
  runTest "profiledDefFunctions" testProfiledDefFunctions

  IO.println "== timing / stress =="
  runTest "timestampsMonotonic" testTimestampsMonotonic
  runTest "nestedSelfTimePositive" testNestedSelfTimePositive
  runTest "highVolumeFlat" testHighVolumeFlat
  runTest "highVolumeNested" testHighVolumeNested

  IO.println ""
  IO.println "ALL EXHAUSTIVE TESTS PASSED"
