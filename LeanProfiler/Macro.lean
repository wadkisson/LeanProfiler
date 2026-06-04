module

public import LeanProfiler.Basic
public meta import LeanProfiler.Option
public meta import LeanProfiler.Attr
public meta import Lean.Elab.Command

open Lean Elab Command

@[expose] public meta section

meta initialize autoInstrumentGuard : IO.Ref Bool ← IO.mkRef false

def monadicTypeNames : List Name := [`IO, `EIO, `BaseIO]
def skippedReturnNames : List Name := [`Except, `Result]

partial def syntaxContainsIdent (stx : Syntax) (names : List Name) : Bool :=
  if stx.isIdent && names.contains stx.getId then
    true
  else
    stx.getArgs.any (syntaxContainsIdent · names)

/-- `register_label_attr profile` uses `Parser.Attr.profile`, not `Attr.simple`. -/
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

/-- Return type is `IO` / `EIO` / `BaseIO` (safe for `withProfileWhenActive`). -/
def isIOReturnShape (sig : Syntax) : Bool :=
  syntaxContainsIdent sig monadicTypeNames

def isSkippedReturnShape (sig : Syntax) : Bool :=
  syntaxContainsIdent sig skippedReturnNames

/-- `@[profile]` on a `do` body whose return is inferred `IO` (signature may omit `IO` ident). -/
def isProfileIODo (modifiers : Syntax) (sig body : Syntax) : Bool :=
  hasProfileAttr modifiers && body.isOfKind ``Parser.Term.do && !isSkippedReturnShape sig

/-- `@[profile]` or legacy `profiler.instrument` on this file. -/
def shouldInstrument (opts : Options) (modifiers : Syntax) : Bool :=
  hasProfileAttr modifiers || profiler.instrument.get opts

/-- Fully qualified name for the def being declared (avoids `_root_.abs`-style collisions). -/
def elaboratedDeclName (shortName : Name) : CommandElabM Name := do
  let ns ← getCurrNamespace
  pure (ns.append shortName)

def rootIdent (nameIdent : Syntax) (shortName : Name) : CommandElabM (TSyntax `ident) := do
  let full ← elaboratedDeclName shortName
  let rootName := `_root_ ++ full
  pure ⟨mkIdentFrom nameIdent rootName⟩

def profileLabel (shortName : Name) : CommandElabM (TSyntax `term) := do
  let full ← elaboratedDeclName shortName
  pure ⟨Syntax.mkStrLit full.toString⟩

def wrapProfiledDef (opts : Options) (nameIdent : Syntax) (declName : Name) (sig : Syntax)
    (body : Syntax) (ioWrap : Bool) : CommandElabM Unit := do
  let nameIdentT ← rootIdent nameIdent declName
  let sigT : TSyntax `Lean.Parser.Command.optDeclSig := ⟨sig⟩
  let nameStr ← profileLabel declName
  let nameStrTerm : TSyntax `term := nameStr
  let bodyTerm : TSyntax `term := ⟨body⟩
  let bodyWrapper ←
    if ioWrap then
      `(withProfileWhenActive $nameStrTerm $bodyTerm)
    else
      `(profilePure $nameStrTerm $bodyTerm)
  let newCmd ←
    if profiler.pure.get opts then
      `(unsafe def $nameIdentT:ident $sigT:optDeclSig := $bodyWrapper)
    else
      `(def $nameIdentT:ident $sigT:optDeclSig := $bodyWrapper)
  autoInstrumentGuard.set true
  elabCommand newCmd
  autoInstrumentGuard.set false

@[command_elab Lean.Parser.Command.declaration]
meta def elabAutoInstrument : CommandElab := fun stx => do
  let guard ← autoInstrumentGuard.get
  if guard then throwUnsupportedSyntax
  let opts ← getOptions
  let modifiers := stx[0]
  unless shouldInstrument opts modifiers do
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
  unless hasProfileAttr modifiers do
    if declName == `main then
      throwUnsupportedSyntax
  if profiler.instrument.get opts && !hasProfileAttr modifiers &&
      body.isOfKind ``Parser.Term.do && !isIOReturnShape sig && !profiler.pure.get opts then
    throwUnsupportedSyntax
  if isIOReturnShape sig || isProfileIODo modifiers sig body then
    wrapProfiledDef opts nameIdent declName sig body (ioWrap := true)
  else if profiler.pure.get opts then
    wrapProfiledDef opts nameIdent declName sig body (ioWrap := false)
  else if hasProfileAttr modifiers then
    logWarning m!"@[profile] on `{declName}`: enable `set_option profiler.pure true` for pure defs"
    throwUnsupportedSyntax
  else
    throwUnsupportedSyntax
