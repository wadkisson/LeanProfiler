module

public import LeanProfiler.Timer
public meta import Lean.LabelAttribute
public meta import Lean.Elab.Command

open Lean Elab Command

@[expose] public meta section

register_label_attr profile

meta initialize autoInstrumentGuard : IO.Ref Bool ← IO.mkRef false

def monadicTypeNames : List Name := [`IO, `EIO, `BaseIO]
def skippedReturnNames : List Name := [`Except, `Result]

partial def syntaxContainsIdent (stx : Syntax) (names : List Name) : Bool :=
  if stx.isIdent && names.contains stx.getId then
    true
  else
    stx.getArgs.any (syntaxContainsIdent · names)

def profileAttrKind : Name := `Parser.Attr.profile

partial def syntaxHasProfileAttr (stx : Syntax) : Bool :=
  if stx.isOfKind profileAttrKind then
    true
  else if stx.isOfKind ``Parser.Attr.simple && stx[0].getId == `profile then
    true
  else
    stx.getArgs.any syntaxHasProfileAttr

def hasProfileAttr (modifiers : Syntax) : Bool :=
  syntaxHasProfileAttr modifiers

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

def wrapProfiledDef (nameIdent : Syntax) (declName : Name) (sig : Syntax) (body : Syntax) :
    CommandElabM Unit := do
  let nameIdentT ← rootIdent nameIdent declName
  let sigT : TSyntax `Lean.Parser.Command.optDeclSig := ⟨sig⟩
  let nameStr ← profileLabel declName
  let bodyTerm : TSyntax `term := ⟨body⟩
  let newCmd ←
    `(def $nameIdentT:ident $sigT:optDeclSig := profile $nameStr $bodyTerm)
  autoInstrumentGuard.set true
  elabCommand newCmd
  autoInstrumentGuard.set false

@[command_elab Lean.Parser.Command.declaration]
meta def elabAutoInstrument : CommandElab := fun stx => do
  let guard ← autoInstrumentGuard.get
  if guard then throwUnsupportedSyntax
  let modifiers := stx[0]
  unless hasProfileAttr modifiers do
    throwUnsupportedSyntax
  let declBody := stx[1]
  unless declBody.isOfKind ``Lean.Parser.Command.definition do
    throwUnsupportedSyntax
  if modifiersContain modifiers ``Lean.Parser.Command.partial then
    throwUnsupportedSyntax
  let declVal := declBody[3]
  unless declVal.isOfKind ``Lean.Parser.Command.declValSimple do
    throwUnsupportedSyntax
  let declId := declBody[1]
  let sig := declBody[2]
  let body := declVal[1]
  let nameIdent := declId[0]
  let declName := nameIdent.getId
  if (`LeanProfiler).isPrefixOf declName then
    throwUnsupportedSyntax
  if isIOReturnShape sig || isProfileIODo modifiers sig body then
    wrapProfiledDef nameIdent declName sig body
  else
    logWarning m!"@[profile] on `{declName}`: only IO `def`s are supported"
    throwUnsupportedSyntax
