/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Cubides
-/

import Argus
import Argus.Term

/-!
# argus demo

One `Command` value drives everything: parsing, colored help, and three shell completion
scripts. Nothing here is written twice.
-/

open Argus
open TermColor

private def demoScheme : ColorScheme := ColorScheme.catppuccin

structure Opts where
  ignoreCase : Bool
  lineNumber : Bool
  jobs : Nat
  pattern : String
  files : List String
  deriving Repr

/-- Built with the combinator front door. No grade is written by hand. -/
def grepishSpec :=
  Spec.seq (Spec.seq (Spec.seq (Spec.seq
    (Spec.map Opts.mk
      (Spec.switch "ignore-case" (some 'i') "Match without regard to case"))
      (Spec.switch "line-number" (some 'n') "Prefix matches with line numbers"))
      (Spec.flag "jobs" (some 'j') "Number of worker threads" Param.nat))
      (Spec.arg "PATTERN" "Pattern to search for" Param.str))
      (Spec.many (Spec.arg "FILE" "Files to search" Param.path))

def grepish :=
  Argus.cmd "grepish" grepishSpec
    (version := some "0.1.0")
    (description := "Search text with an inspectable command line.")

private def rule (title : String) : IO Unit := do
  IO.println ""
  IO.println s!"───── {title} ─────"

private def runOpts (opts : Opts) : IO UInt32 := do
  IO.println (repr opts)
  pure 0

private def demo : IO UInt32 := do
  -- With no arguments, show what one Command value produces.
  rule "COLORED HELP"
  IO.print (Help.renderTo RenderTarget.trueColor grepish 80 demoScheme)

  rule "A SUCCESSFUL PARSE"
  IO.println "argv: -i --jobs 4 needle src/a.lean src/b.lean"
  match grepish.run ["-i", "--jobs", "4", "needle", "src/a.lean", "src/b.lean"] with
  | .ok o => IO.println (repr o)
  | .error es => for e in es do IO.println s!"unexpected: {e.message}"

  rule "ACCUMULATED ERRORS (not just the first)"
  IO.println "argv: --jobs=12x --ignor-case needle"
  match grepish.run ["--jobs=12x", "--ignor-case", "needle"] with
  | .ok o => IO.println s!"unexpected success: {repr o}"
  | .error es => do
      IO.print (Text.render RenderTarget.trueColor (Help.renderErrors es demoScheme))

  rule "BASH COMPLETIONS"
  IO.print (Completions.bash grepish)

  rule "ZSH COMPLETIONS"
  IO.print (Completions.zsh grepish)

  rule "FISH COMPLETIONS"
  IO.print (Completions.fish grepish)

  pure 0

def main (argv : List String) : IO UInt32 :=
  if argv.isEmpty then
    demo
  else
    Term.main grepish argv runOpts (scheme := demoScheme)
