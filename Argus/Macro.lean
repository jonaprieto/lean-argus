/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

import Argus.Spec

/-!
# Argus.Macro: the `argus_opts` front door

`argus_opts` emits a structure and its ordered `Spec` together. The default spelling uses a
semicolon after each field because an unconstrained Lean `term` consumes the next field name
as an application across a newline. No elaborator imports are needed; the macro only rewrites
core syntax and quotations.
-/

syntax argusField := ident " : " term " := " term
syntax "argus_opts " ident " where" sepBy1(argusField, ";") : command

macro_rules
  | `(command| argus_opts $name:ident where $[$f:ident : $t:term := $s:term];*) => do
    let rec makeFields (i : Nat) (acc : Array Lean.Syntax) : Lean.MacroM (Array Lean.Syntax) := do
      if h : i < f.size then
        let fi := f[i]!
        let ti := t[i]!
        let one ← `(structure $name where $fi:ident : $ti:term)
        let structureNode := one.raw.getArg 1
        let whereNode := structureNode.getArg 4
        let fieldsNode := whereNode.getArg 2
        makeFields (i + 1) (acc.push (fieldsNode.getArg 0 |>.getArg 0))
      else
        pure acc
    let fields ← makeFields 0 #[]
    let ctorName := Lean.mkIdent (name.getId ++ `mk)
    let f0 := f[0]!
    let mut constructor ← `( $ctorName:ident $f0:ident )
    for i in (List.range f.size).drop 1 do
      let fi := f[i]!
      constructor ← `($constructor:term $fi:ident)
    for i in (List.range f.size).reverse do
      let fi := f[i]!
      constructor ← `(fun $fi:ident => $constructor:term)
    let s0 := s[0]!
    let mut spec ← `(Argus.Spec.map $constructor:term $s0:term)
    for i in (List.range f.size).drop 1 do
      let si := s[i]!
      spec ← `(Argus.Spec.seq $spec:term $si:term)
    let specName := Lean.mkIdent (name.getId ++ `spec)
    let result ← `(structure $name where field : Nat
      def $specName:ident := (show Argus.Spec _ $name:ident from $spec:term))
    let declaration := result.raw.getArg 0
    let structureNode := declaration.getArg 1
    let whereNode := structureNode.getArg 4
    let fieldsNode := whereNode.getArg 2
    let fieldGroup := fieldsNode.getArg 0
    let fieldGroup := .node .none fieldGroup.getKind fields
    let fieldsNode := .node .none fieldsNode.getKind #[fieldGroup]
    let whereNode := .node .none whereNode.getKind (whereNode.getArgs.set! 2
      fieldsNode)
    let structureNode := .node .none structureNode.getKind
      (structureNode.getArgs.set! 4 whereNode)
    let declaration := .node .none declaration.getKind
      (declaration.getArgs.set! 1 structureNode)
    let result := .node .none result.raw.getKind (result.raw.getArgs.set! 0 declaration)
    pure (show Lean.TSyntax `command from Lean.TSyntax.mk result)
