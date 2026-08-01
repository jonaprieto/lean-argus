/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Cubides
-/

import Argus.Command
import TermColor.Layout

/-!
# Argus.Help: colored help, derived from the spec

Help is computed from `Spec.toMeta`, never written alongside it, so the two cannot drift.
That is what makes `help_sound` provable.

Alignment uses `TermColor.Text.width` (display cells) rather than `String.length`, so a
description containing CJK or emoji still lines up.

`width` is a parameter, not detected. This keeps `Argus.Help` pure and free of
`termcolor-terminal`; the caller supplies the real terminal width if it wants one. That
is the same division `termcolor-widgets` documents: the caller owns terminal size.
-/

namespace Argus.Help

open TermColor
open scoped TermColor.Style

variable {g : Grade} {α : Type}

private def titleStyle : Style := Style.bold <+> Style.cyan
private def sectionStyle : Style := Style.bold <+> Style.blue
private def flagStyle : Style := Style.bold <+> Style.green

private def nl (t : Text) : Text := t ++ Text.plain "\n"

/-- Two-column rows, aligned on display width, wrapped to `width`. -/
private def rows (width : Nat) (items : List (Text × Text)) : Text :=
  if items.isEmpty then Text.plain "" else
  let labelWidth := items.foldl (fun acc it => max acc it.1.width) 0
  let gap := 2
  let descWidth := if width > labelWidth + gap + 4 then width - labelWidth - gap else 20
  Text.concat <| items.map fun (label, desc) =>
    let wrapped := Layout.wrapLines descWidth desc
    nl (Layout.padRight labelWidth label ++ Text.plain "  " ++ wrapped)

private def block (title : String) (body : Text) : Text :=
  if body.plainText.isEmpty then Text.plain ""
  else nl (Text.styled title sectionStyle) ++ body ++ Text.plain "\n"

/-- `-i, --ignore-case` or `-j, --jobs NAT`. -/
private def flagLabel (f : FlagInfo) : Text :=
  let long := Text.styled ("--" ++ f.long) flagStyle
  let both := match f.short with
    | some c => Text.styled ("-" ++ c.toString) flagStyle ++ Text.plain ", " ++ long
    | none => long
  match f.typeName with
  | none => both
  | some t => both ++ Text.plain (" " ++ t)

private def argLabel (a : ArgInfo) : Text :=
  Text.styled ("<" ++ a.name ++ ">" ++ (if a.variadic then "..." else "")) Style.bold
    ++ Text.plain (" " ++ a.typeName)

/-- Render a command's help page. -/
def render (c : Command g α) (width : Nat := 80) : Text :=
  let m := c.toMeta
  let version := match c.version with
    | some v => " " ++ v
    | none => ""
  let header :=
    nl (Text.styled (c.name ++ version) titleStyle) ++
    (if c.description.isEmpty then Text.plain ""
     else nl (Text.styled c.description Style.dim)) ++
    Text.plain "\n"
  header
    ++ block "USAGE" (nl (Text.plain ("  " ++ c.usageLine)))
    ++ block "FLAGS" (rows width (m.flags.map fun f => (flagLabel f, Text.plain f.help)))
    ++ block "ARGS" (rows width (m.args.map fun a => (argLabel a, Text.plain a.help)))

/-- Render to a string for a known target. -/
def renderTo (target : RenderTarget) (c : Command g α) (width : Nat := 80) : String :=
  Text.render target (render c width)

/-- Render errors as a styled block, one per line. -/
def renderErrors (errs : List Err) : Text :=
  Text.concat <| errs.map fun e =>
    nl (Text.styled "error" (Style.bold <+> Style.red)
        ++ Text.plain (": " ++ e.message))

end Argus.Help
