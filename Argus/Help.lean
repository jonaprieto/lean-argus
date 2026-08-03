/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Cubides
-/

import Argus.Command
import Argus.Diagnostics
import TermColor.Layout
import TermColor.ColorScheme

/-!
# Argus.Help: colored help, derived from the spec

Command-specific help is computed from `Spec.toMeta`, never written alongside it, so the two
cannot drift. The optional terminal flags document the controls provided by `Argus.Term`.
That is what makes `help_sound` provable.

Semantic styles use `ColorScheme.catppuccin` by default; callers can supply another
`ColorScheme` without changing the command or its layout.

Alignment uses `TermColor.Text.width` (display cells) rather than `String.length`, so a
description containing CJK or emoji still lines up.

`width` is a parameter, not detected. This keeps `Argus.Help` pure and free of
`termcolor-terminal`; the caller supplies the real terminal width if it wants one. That
is the same division `termcolor-widgets` documents: the caller owns terminal size.
-/

namespace Argus.Help

open TermColor
open scoped TermColor.Style

variable {α : Type}

private def titleStyle (scheme : ColorScheme) : Style :=
  Style.bold <+> Style.fg scheme.cyan
private def sectionStyle (scheme : ColorScheme) : Style :=
  Style.bold <+> Style.fg scheme.purple
private def commandStyle (scheme : ColorScheme) : Style :=
  Style.bold <+> Style.fg scheme.cyan
private def flagStyle (scheme : ColorScheme) : Style :=
  Style.bold <+> Style.fg scheme.green
private def argStyle (scheme : ColorScheme) : Style :=
  Style.bold <+> Style.fg scheme.yellow
private def typeStyle (scheme : ColorScheme) : Style := Style.fg scheme.orange
private def descriptionStyle (scheme : ColorScheme) : Style := Style.fg scheme.foreground
private def mutedStyle (scheme : ColorScheme) : Style :=
  Style.dim <+> Style.fg scheme.comment

private def nl (t : Text) : Text := t ++ Text.plain "\n"

/-- Two-column rows, aligned on display width, wrapped to `width`.

Only the label column is padded. `Layout.columns` would be shorter, but it aligns *every*
column including the last, which leaves trailing spaces on every help line. Splitting the
wrapped description with `Layout.splitLines` and indenting the continuation lines by hand
gives the same alignment with no trailing whitespace. -/
private def rows (width : Nat) (items : List (Text × Text)) : Text :=
  if items.isEmpty then Text.plain "" else
  let labelWidth := items.foldl (fun acc it => max acc it.1.width) 0
  let gap := 2
  let descWidth := if width > labelWidth + gap + 4 then width - labelWidth - gap else 20
  let indent := Text.plain (String.ofList (List.replicate (labelWidth + gap) ' '))
  let sep := Text.plain (String.ofList (List.replicate gap ' '))
  Layout.joinLines (items.map fun (label, desc) =>
    match Layout.splitLines (Layout.wrapLines descWidth desc) with
    | [] => label
    | first :: rest =>
      Layout.joinLines
        ((Layout.padRight labelWidth label ++ sep ++ first) :: rest.map (indent ++ ·)))
    ++ Text.plain "\n"

private def block (scheme : ColorScheme) (title : String) (body : Text) : Text :=
  if body.plainText.isEmpty then Text.plain ""
  else nl (Text.styled title (sectionStyle scheme)) ++ body ++ Text.plain "\n"

/-- `-i, --ignore-case` or `-j, --jobs NAT`. -/
private def flagLabel (scheme : ColorScheme) (f : FlagInfo) : Text :=
  let long := Text.styled ("--" ++ f.long) (flagStyle scheme)
  let both := match f.short with
    | some c => Text.styled ("-" ++ c.toString) (flagStyle scheme) ++ Text.plain ", " ++ long
    | none => long
  match f.typeName with
  | none => both
  | some t => both ++ Text.styled (" " ++ t) (typeStyle scheme)

private def argLabel (scheme : ColorScheme) (a : ArgInfo) : Text :=
  Text.styled ("<" ++ a.name ++ ">" ++ (if a.variadic then "..." else "")) (argStyle scheme)
    ++ Text.styled (" " ++ a.typeName) (typeStyle scheme)

private def subcommandLabel (scheme : ColorScheme) (name : String) : Text :=
  Text.styled name (commandStyle scheme)

private def globalFlags (scheme : ColorScheme) : List (Text × Text) :=
  [ (Text.styled "-h, --help" (flagStyle scheme),
      Text.styled "Show this help page" (descriptionStyle scheme))
  , (Text.styled "--version" (flagStyle scheme),
      Text.styled "Show the command version" (descriptionStyle scheme))
  , (Text.styled "--completions" (flagStyle scheme) ++
      Text.styled " SHELL" (typeStyle scheme),
      Text.styled "Print a shell completion script" (descriptionStyle scheme))
  ]

private def usageText (scheme : ColorScheme) (c : Command α) : Text :=
  let command := Text.styled c.name (commandStyle scheme)
  match c.body with
  | .subs _ => command ++ Text.styled " <SUBCOMMAND>" (argStyle scheme)
  | .opts _ =>
    let m := c.toMeta
    let flags := if m.flags.isEmpty then Text.empty
      else Text.styled " [FLAGS]" (flagStyle scheme)
    let args := Text.concat <| m.args.map fun a =>
      Text.styled (" <" ++ a.name ++ ">" ++ (if a.variadic then "..." else ""))
        (argStyle scheme)
    command ++ flags ++ args

/-- Render a command's help page. `includeGlobals` adds the standard `Argus.Term` controls. -/
def render (c : Command α) (width : Nat := 80)
    (scheme : ColorScheme := ColorScheme.catppuccin) (includeGlobals : Bool := false) : Text :=
  let version := match c.version with
    | some v => " " ++ v
    | none => ""
  let header :=
    nl (Text.styled (c.name ++ version) (titleStyle scheme)) ++
    (if c.description.isEmpty then Text.plain ""
     else nl (Text.styled c.description (mutedStyle scheme))) ++
    Text.plain "\n"
  let extraFlags := if includeGlobals then globalFlags scheme else []
  let body := match c.body with
    | .opts _ =>
      let m := c.toMeta
      block scheme "FLAGS"
          (rows width (extraFlags ++ m.flags.map fun f =>
            (flagLabel scheme f, Text.styled f.help (descriptionStyle scheme))))
        ++ block scheme "ARGS"
          (rows width (m.args.map fun a =>
            (argLabel scheme a, Text.styled a.help (descriptionStyle scheme))))
    | .subs children =>
      block scheme "FLAGS" (rows width extraFlags) ++
        block scheme "SUBCOMMANDS"
        (rows width (children.map fun child =>
          (subcommandLabel scheme child.name,
            Text.styled child.description (descriptionStyle scheme))))
  header ++ block scheme "USAGE" (nl (Text.plain "  " ++ usageText scheme c)) ++ body

/-- Render to a string for a known target. -/
def renderTo (target : RenderTarget) (c : Command α) (width : Nat := 80)
    (scheme : ColorScheme := ColorScheme.catppuccin) (includeGlobals : Bool := false) : String :=
  Text.render target (render c width scheme includeGlobals)

/-- Render errors with source labels for positioned value failures. -/
def renderErrors (errs : List Err)
    (scheme : ColorScheme := ColorScheme.catppuccin) : Text :=
  let report := errorsToDiagnostics errs
  TermColor.Diagnostics.renderMany report.sources report.diagnostics {} scheme

end Argus.Help
