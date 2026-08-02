/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Cubides
-/

import Argus.Help
import Argus.Completions
import TermColor.Terminal
import TermColor.ColorScheme

/-!
# Argus.Term: the IO layer

`Argus.Help` is pure and takes `width` as a parameter. This module is where the terminal
actually gets asked: `terminalWidth` for the real width, `TermColor.print` for a target
chosen from the environment (so `NO_COLOR` and `FORCE_COLOR` are honored without Argus
reimplementing either).

Importing this pulls in `termcolor-terminal`. Anyone who only wants parsing, or who
renders to a fixed width, should import `Argus` instead and never pay for it.
-/

namespace Argus.Term

open TermColor

variable {α : Type}

/-- Print help to stdout, at the real terminal width, in whatever color the environment
allows. -/
def printHelp (c : Command α) (choice : ColorChoice := .auto)
    (scheme : ColorScheme := ColorScheme.catppuccin) : IO Unit := do
  let width ← Terminal.terminalWidth
  TermColor.print (Help.render c width scheme (includeGlobals := true)) choice

/-- Print errors to stderr. Diagnostics belong on stderr so `tool 2>/dev/null` still
works and piping stdout stays clean. -/
def printErrors (errs : List Err) (choice : ColorChoice := .auto)
    (scheme : ColorScheme := ColorScheme.catppuccin) : IO Unit := do
  let target ← TermColor.target choice
  (← IO.getStderr).putStr (Text.render target (Help.renderErrors errs scheme))

/-- Exit codes: `0` success, `1` runtime failure, `2` usage error. -/
def usageExit : UInt32 := 2

/-- A complete entry point.

Handles `--help`, `--version`, and `--completions SHELL` before parsing, so none of them
require the command's mandatory flags to be present. On a parse failure it reports every
error and the help page, then exits `2`. Otherwise it hands the typed value to `body`.

```lean
def main (argv : List String) : IO UInt32 :=
  Argus.Term.main grepish argv fun opts => do
    IO.println s!"searching for {opts.pattern}"
    return 0
```
-/
def main (c : Command α) (argv : List String) (body : α → IO UInt32)
    (scheme : ColorScheme := ColorScheme.catppuccin) : IO UInt32 := do
  -- `--help` is honoured wherever it appears, and reports the deepest subcommand reached:
  -- `tool build --help` documents `build`, not `tool`. Matching only `["--help"]` at the
  -- root would send it down to the child, which would reject it as an unknown flag.
  if argv.contains "--help" || argv.contains "-h" then
    printHelp (c.resolve argv) .auto scheme
    return 0
  if argv.contains "--version" then
    let target := c.resolve argv
    match target.version <|> c.version with
    | some v => IO.println s!"{target.name} {v}"; return 0
    | none => IO.println target.name; return 0
  match argv with
  | ["--completions", shell] =>
    match shell with
    | "bash" => IO.print (Completions.bash c); return 0
    | "zsh" => IO.print (Completions.zsh c); return 0
    | "fish" => IO.print (Completions.fish c); return 0
    | other =>
      IO.eprintln s!"{c.name}: unknown shell '{other}' (want bash, zsh, or fish)"
      return usageExit
  | _ =>
    match c.run argv with
    | .ok value => body value
    | .error errs =>
      printErrors errs .auto scheme
      printHelp c .auto scheme
      return usageExit

end Argus.Term
