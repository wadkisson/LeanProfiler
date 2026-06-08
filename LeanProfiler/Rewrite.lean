module

public import LeanProfiler.Timer
public import LeanProfiler.Summary
public meta import Lean.LabelAttribute
public meta import Lean.Elab.Command
public meta import Lean.Parser.Do

open Lean Elab Command Parser.Term

@[expose] public meta section

register_label_attr profile

public register_option profile_main : Bool := {
  defValue := true
  descr := "auto-profile top-level calls in `main` and print summary + trace on exit"
}

meta initialize autoInstrumentGuard : IO.Ref Bool ← IO.mkRef false

def monadicTypeNames : List Name := [`IO, `EIO, `BaseIO]
def skippedReturnNames : List Name := [`Except, `Result]

partial def syntaxContainsIdent (stx : Syntax) (names : List Name) : Bool :=
  if stx.isIdent && names.contains stx.getId then
    true
  else
    stx.getArgs.any (syntaxContainsIdent · names)

def profileAttrKind : Name := `Parser.Attr.profile

partial def syntaxHasAttr (stx : Syntax) (kind : SyntaxNodeKind) (name : Name) : Bool :=
  if stx.isOfKind kind then
    true
  else if stx.isOfKind ``Parser.Attr.simple && stx[0].getId == name then
    true
  else
    stx.getArgs.any (syntaxHasAttr · kind name)

def hasProfileAttr (modifiers : Syntax) : Bool :=
  syntaxHasAttr modifiers profileAttrKind `profile

def modifiersContain (modifiers : Syntax) (kind : SyntaxNodeKind) : Bool :=
  modifiers.find? (·.isOfKind kind) |>.isSome

def isIOReturnShape (sig : Syntax) : Bool :=
  syntaxContainsIdent sig monadicTypeNames

def isSkippedReturnShape (sig : Syntax) : Bool :=
  syntaxContainsIdent sig skippedReturnNames

def isProfileIODo (modifiers : Syntax) (sig body : Syntax) : Bool :=
  hasProfileAttr modifiers && body.isOfKind ``Parser.Term.do && !isSkippedReturnShape sig

def elaboratedDeclName (shortName : Name) : CommandElabM Name := do
  let ns ← getCurrNamespace
  pure (ns.append shortName)

def rootIdent (nameIdent : Syntax) (shortName : Name) : CommandElabM (TSyntax `ident) := do
  let full ← elaboratedDeclName shortName
  pure ⟨mkIdentFrom nameIdent (`_root_ ++ full)⟩

def profileLabel (shortName : Name) : CommandElabM (TSyntax `term) := do
  let full ← elaboratedDeclName shortName
  pure ⟨Syntax.mkStrLit full.toString⟩

def skippedCallRoots : List Name := [
  `IO, `Init, `Std, `Lean, `String, `List, `Array, `Nat, `Int, `Bool, `UInt8, `UInt16, `UInt32, `UInt64,
  `USize, `Float, `Char, `System, `Lake, `Option, `Except, `Repr, `ToString, `Decidable, `Unit, `PUnit,
  `Pure, `bind, `seq, `Functor, `Monad, `ExceptT, `ReaderT, `StateT, `EIO, `BaseIO,
  `recordSpan, `withProfile, `profileAfter, `profileLet, `profileEnd, `profileReturn,
  `dbg_trace, `idbg, `assert!, `pure, `return
]

def isSkippedCallHead (name : Name) : Bool :=
  let n := name.eraseMacroScopes
  n == `main ||
    (`LeanProfiler).isPrefixOf n ||
    skippedCallRoots.any (·.isPrefixOf n)

partial def callHeadName? (stx : Syntax) : Option Name :=
  if stx.isIdent then
    some stx.getId
  else if stx.isOfKind ``Parser.Term.app then
    callHeadName? stx[0]
  else if stx.isOfKind ``Parser.Term.paren then
    if stx.getNumArgs ≥ 2 then callHeadName? stx[1] else none
  else if stx.isOfKind ``Parser.Term.dotIdent then
    some stx[0].getId
  else
    none

def isAlreadyProfiled (stx : Syntax) : Bool :=
  match stx with
  | `(recordSpan $_ $_) => true
  | `(withProfile $_ $_) => true
  | `(profile $_ do $_) => true
  | `(profileLet $_ $_ $_) => true
  | _ =>
    stx.isOfKind ``Parser.Term.app &&
      (stx[0].isIdent && (stx[0].getId == `recordSpan || stx[0].getId == `withProfile || stx[0].getId == `profileLet))

def spanLabelForCall (head : Name) : CommandElabM (TSyntax `term) := do
  let n := head.eraseMacroScopes
  if n.isAtomic then
    profileLabel n
  else
    pure ⟨Syntax.mkStrLit n.toString⟩

def instrumentCallTerm (stx : TSyntax `term) : CommandElabM (TSyntax `term) := do
  if isAlreadyProfiled stx.raw then
    return stx
  match callHeadName? stx.raw with
  | some head =>
    if isSkippedCallHead head then
      return stx
    else
      let label ← spanLabelForCall head
      `(recordSpan $label $stx)
  | none =>
    return stx

mutual

partial def instrumentDoElem (elem : Syntax) : CommandElabM Syntax := do
  let kind := elem.getKind
  if kind == ``Parser.Term.doExpr then
    let newTerm ← instrumentCallTerm ⟨elem[0]⟩
    return elem.setArg 0 newTerm.raw
  else if kind == ``Parser.Term.doLetArrow || kind == ``Parser.Term.doReassignArrow then
    let bind := elem[elem.getNumArgs - 1]
    if bind.getKind == ``Parser.Term.doIdDecl || bind.getKind == ``Parser.Term.doPatDecl then
      let subIdx := bind.getNumArgs - 1
      let newSub ← instrumentDoElem bind[subIdx]
      return elem.setArg (elem.getNumArgs - 1) (bind.setArg subIdx newSub)
    else
      return elem
  else if kind == ``Parser.Term.doLet then
    let decl := elem[elem.getNumArgs - 1]
    if decl.isOfKind ``Parser.Term.letIdDecl || decl.isOfKind ``Parser.Term.letPatDecl then
      let rhsIdx := decl.getNumArgs - 1
      let newRhs ← instrumentCallTerm ⟨decl[rhsIdx]⟩
      return elem.setArg (elem.getNumArgs - 1) (decl.setArg rhsIdx newRhs.raw)
    else
      return elem
  else if kind == ``Parser.Term.doFor then
    let bodyIdx := elem.getNumArgs - 1
    let newBody ← instrumentDoSeqRaw elem[bodyIdx]
    return elem.setArg bodyIdx newBody
  else if kind == ``Parser.Term.doIf || kind == ``Parser.Term.doIfLet then
    let mut e := elem
    for i in [2:elem.getNumArgs] do
      if elem[i].isOfKind ``Parser.Term.doSeq then
        let newSeq ← instrumentDoSeqRaw elem[i]
        e := e.setArg i newSeq
    return e
  else if kind == ``Parser.Term.doUnless then
    let bodyIdx := elem.getNumArgs - 1
    let newBody ← instrumentDoSeqRaw elem[bodyIdx]
    return elem.setArg bodyIdx newBody
  else
    return elem

partial def instrumentDoSeqRaw (doSeq : Syntax) : CommandElabM Syntax := do
  let elems := getDoElems ⟨doSeq⟩
  let newElems ← elems.mapM fun elem => do
    let newRaw ← instrumentDoElem elem.raw
    pure (⟨newRaw⟩ : TSyntax `doElem)
  let info := doSeq.getHeadInfo
  pure (Syntax.node1 info ``Parser.Term.doSeq (Syntax.node info `null (Array.map (·.raw) newElems)))

end

def instrumentMainBody (body : Syntax) : CommandElabM (TSyntax `term) := do
  match body with
  | `(do $doSeq:doSeq) =>
    let elems := getDoElems doSeq
    let newElems ← elems.mapM fun elem => do
      let newRaw ← instrumentDoElem elem.raw
      pure (⟨newRaw⟩ : TSyntax `doElem)
    `(do $[$newElems:doElem]*)
  | _ =>
    instrumentCallTerm ⟨body⟩

/-- Like `instrumentMainBody`, but also walks `fun _ => do` bodies (e.g. `withModel` callbacks). -/
partial def instrumentProfileTerm (stx : Syntax) : CommandElabM Syntax := do
  if stx.isOfKind ``Parser.Term.do then
    let newTerm ← instrumentMainBody stx
    pure newTerm.raw
  else if stx.isOfKind ``Parser.Term.fun then
    let bodyIdx := stx.getNumArgs - 1
    let newBody ← instrumentProfileTerm stx[bodyIdx]
    pure (stx.setArg bodyIdx newBody)
  else if stx.isOfKind ``Parser.Term.app then
    let mut e := stx
    for i in [1:stx.getNumArgs] do
      let newArg ← instrumentProfileTerm stx[i]
      e := e.setArg i newArg
    pure e
  else if stx.isOfKind ``Parser.Term.paren && stx.getNumArgs ≥ 2 then
    let newInner ← instrumentProfileTerm stx[1]
    pure (stx.setArg 1 newInner)
  else
    pure stx

def instrumentProfileBody (body : Syntax) : CommandElabM (TSyntax `term) := do
  let newRaw ← instrumentProfileTerm body
  pure ⟨newRaw⟩

def wrapProfiledDef (nameIdent : Syntax) (declName : Name) (sig : Syntax) (body : Syntax) :
    CommandElabM Unit := do
  let nameIdentT ← rootIdent nameIdent declName
  let sigT : TSyntax `Lean.Parser.Command.optDeclSig := ⟨sig⟩
  let nameStr ← profileLabel declName
  let bodyTerm ← instrumentProfileBody body
  let newCmd ←
    `(def $nameIdentT:ident $sigT:optDeclSig := recordSpan $nameStr $bodyTerm)
  autoInstrumentGuard.set true
  elabCommand newCmd
  autoInstrumentGuard.set false

def wrapProfileMainDef (nameIdent : Syntax) (declName : Name) (sig : Syntax) (body : Syntax) :
    CommandElabM Unit := do
  let nameIdentT ← rootIdent nameIdent declName
  let sigT : TSyntax `Lean.Parser.Command.optDeclSig := ⟨sig⟩
  let bodyTerm ←
    if profile_main.get (← getOptions) then
      instrumentMainBody body
    else
      pure ⟨body⟩
  let newCmd ←
    `(def $nameIdentT:ident $sigT:optDeclSig := profileAfter $bodyTerm)
  autoInstrumentGuard.set true
  elabCommand newCmd
  autoInstrumentGuard.set false

def wrapProfileMainWithAttr (nameIdent : Syntax) (declName : Name) (sig : Syntax) (body : Syntax) :
    CommandElabM Unit := do
  let nameIdentT ← rootIdent nameIdent declName
  let sigT : TSyntax `Lean.Parser.Command.optDeclSig := ⟨sig⟩
  let nameStr ← profileLabel declName
  let bodyTerm ← instrumentProfileBody body
  let newCmd ←
    `(def $nameIdentT:ident $sigT:optDeclSig := profileAfter (recordSpan $nameStr $bodyTerm))
  autoInstrumentGuard.set true
  elabCommand newCmd
  autoInstrumentGuard.set false

def tryWrapProfile (modifiers : Syntax) (declBody : Syntax) : CommandElabM Bool := do
  unless hasProfileAttr modifiers do
    return false
  unless declBody.isOfKind ``Lean.Parser.Command.definition do
    return false
  if modifiersContain modifiers ``Lean.Parser.Command.partial then
    return false
  let declVal := declBody[3]
  unless declVal.isOfKind ``Lean.Parser.Command.declValSimple do
    return false
  let declId := declBody[1]
  let sig := declBody[2]
  let body := declVal[1]
  let nameIdent := declId[0]
  let declName := nameIdent.getId
  if (`LeanProfiler).isPrefixOf declName then
    return false
  unless isIOReturnShape sig || isProfileIODo modifiers sig body do
    logWarning m!"@[profile] on `{declName}`: only IO `def`s are supported"
    return false
  if declName == `main then
    wrapProfileMainWithAttr nameIdent declName sig body
  else
    wrapProfiledDef nameIdent declName sig body
  return true

def tryWrapMain (modifiers : Syntax) (declBody : Syntax) : CommandElabM Bool := do
  if hasProfileAttr modifiers then
    return false
  unless declBody.isOfKind ``Lean.Parser.Command.definition do
    return false
  if modifiersContain modifiers ``Lean.Parser.Command.partial then
    return false
  let declVal := declBody[3]
  unless declVal.isOfKind ``Lean.Parser.Command.declValSimple do
    return false
  let declId := declBody[1]
  let sig := declBody[2]
  let body := declVal[1]
  let nameIdent := declId[0]
  let declName := nameIdent.getId
  unless declName == `main do
    return false
  if (`LeanProfiler).isPrefixOf declName then
    return false
  unless isIOReturnShape sig do
    return false
  wrapProfileMainDef nameIdent declName sig body
  return true

@[command_elab Lean.Parser.Command.declaration]
meta def elabAutoInstrument : CommandElab := fun stx => do
  let guard ← autoInstrumentGuard.get
  if guard then throwUnsupportedSyntax
  let modifiers := stx[0]
  let declBody := stx[1]
  if (← tryWrapProfile modifiers declBody) then
    return
  if (← tryWrapMain modifiers declBody) then
    return
  throwUnsupportedSyntax
