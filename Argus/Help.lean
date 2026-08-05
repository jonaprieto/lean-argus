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
cannot drift. The optional `BASIC OPTIONS` block documents the controls provided by
`Argus.Term`.
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

private def sectionStyle (scheme : ColorScheme) : Style :=
  Style.bold <+> Style.fg scheme.purple
private def commandStyle (scheme : ColorScheme) : Style :=
  Style.bold <+> Style.fg scheme.cyan
private def titleCommandStyle (scheme : ColorScheme) : Style :=
  Style.bold <+> Style.underline <+> Style.fg scheme.pink
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
  let prefixWidth := 2
  let gap := 2
  let descWidth := if width > prefixWidth + labelWidth + gap + 4 then
      width - prefixWidth - labelWidth - gap
    else 20
  let rowPrefix := Text.plain "  "
  let indent := Text.plain
    (String.ofList (List.replicate (prefixWidth + labelWidth + gap) ' '))
  let sep := Text.plain (String.ofList (List.replicate gap ' '))
  Layout.joinLines (items.map fun (label, desc) =>
    match Layout.splitLines (Layout.wrapLines descWidth desc) with
    | [] => label
    | first :: rest =>
      Layout.joinLines
        ((rowPrefix ++ Layout.padRight labelWidth label ++ sep ++ first) :: rest.map (indent ++ ·)))
    ++ Text.plain "\n"

private def block (scheme : ColorScheme) (title : String) (body : Text) : Text :=
  if body.plainText.isEmpty then Text.plain ""
  else nl (Text.styled (title ++ ":") (sectionStyle scheme)) ++ body ++ Text.plain "\n"

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

private def subcommandLabel (scheme : ColorScheme) (c : Command α) : Text :=
  let command := Text.styled c.name (commandStyle scheme)
  match c.body with
  | .subs _ => command
      ++ Text.styled " [OPTIONS]" (flagStyle scheme)
      ++ Text.styled " <COMMAND>" (commandStyle scheme)
  | .opts _ =>
    let m := c.toMeta
    let flags := if m.flags.isEmpty then Text.empty
      else Text.styled " [OPTIONS]" (flagStyle scheme)
    let args := Text.concat <| m.args.map fun a =>
      Text.styled (" <" ++ a.name ++ ">" ++ (if a.variadic then "..." else ""))
        (argStyle scheme)
    command ++ flags ++ args

private def commandName (c : Command α) (path : List String) : String :=
  if path.isEmpty then c.name else " ".intercalate path

private def titleText (scheme : ColorScheme) (c : Command α) (path : List String) : Text :=
  let names := if path.isEmpty then [c.name] else path
  let command := match names with
    | [] => Text.empty
    | first :: rest =>
      rest.foldl (fun text name =>
        text ++ Text.plain " " ++ Text.styled name (commandStyle scheme))
        (Text.styled first (titleCommandStyle scheme))
  let version := match c.version with
    | some v => Text.styled " version " (mutedStyle scheme)
        ++ Text.styled v (typeStyle scheme)
    | none => Text.empty
  let toolchain := match c.toolchain with
    | some t => Text.styled " (" (mutedStyle scheme)
        ++ Text.styled t (descriptionStyle scheme)
        ++ Text.styled ")" (mutedStyle scheme)
    | none => Text.empty
  command ++ version ++ toolchain

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
  | .subs _ => command
      ++ Text.styled " [OPTIONS]" (flagStyle scheme)
      ++ Text.styled " <COMMAND>" (commandStyle scheme)
  | .opts _ =>
    let m := c.toMeta
    let flags := if m.flags.isEmpty then Text.empty
      else Text.styled " [OPTIONS]" (flagStyle scheme)
    let args := Text.concat <| m.args.map fun a =>
      Text.styled (" <" ++ a.name ++ ">" ++ (if a.variadic then "..." else ""))
        (argStyle scheme)
    command ++ flags ++ args

/-- Render a command's help page. `includeGlobals` adds the standard `Argus.Term` controls. -/
def render (c : Command α) (width : Nat := 80)
    (scheme : ColorScheme := ColorScheme.catppuccin) (includeGlobals : Bool := false)
    (commandPath : List String := []) : Text :=
  let name := commandName c commandPath
  let header :=
    nl (titleText scheme c commandPath) ++
    (if c.description.isEmpty then Text.plain ""
     else nl (Text.styled c.description (mutedStyle scheme))) ++
    Text.plain "\n"
  let globals := if includeGlobals then
      block scheme "BASIC OPTIONS" (rows width (globalFlags scheme))
    else Text.empty
  let body := match c.body with
    | .opts _ =>
      let m := c.toMeta
      globals ++ block scheme "OPTIONS"
          (rows width (m.flags.map fun f =>
            (flagLabel scheme f, Text.styled f.help (descriptionStyle scheme))))
        ++ block scheme "ARGS"
          (rows width (m.args.map fun a =>
            (argLabel scheme a, Text.styled a.help (descriptionStyle scheme))))
    | .subs children =>
      globals ++ block scheme "COMMANDS"
        (rows width (children.map fun child =>
          (subcommandLabel scheme child,
            Text.styled child.description (descriptionStyle scheme))))
  let usage := usageText scheme { c with name := name }
  header ++ block scheme "USAGE" (nl (Text.plain "  " ++ usage)) ++ body

/-- Render to a string for a known target. -/
def renderTo (target : RenderTarget) (c : Command α) (width : Nat := 80)
    (scheme : ColorScheme := ColorScheme.catppuccin) (includeGlobals : Bool := false)
    (commandPath : List String := []) : String :=
  Text.render target (render c width scheme includeGlobals commandPath)

/-- Render errors with source labels for positioned value failures. -/
def renderErrors (errs : List Err)
    (scheme : ColorScheme := ColorScheme.catppuccin) : Text :=
  let report := errorsToDiagnostics errs
  TermColor.Diagnostics.renderMany report.sources report.diagnostics {} scheme

end Argus.Help
