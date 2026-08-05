/-
Copyright (c) 2026 Jonathan Prieto-Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Prieto-Cubides
-/

import Argus
import Argus.Term

/-!
# argus demo

One `Command` value drives everything: parsing, structured help, diagnostics, and three shell
completion scripts. The small command tree below keeps only the features worth seeing.
-/

open Argus
open TermColor

private def demoScheme : ColorScheme := ColorScheme.catppuccin

private def buildCommand : Command String :=
  Argus.cmd "build"
    (Spec.map2 (fun (old : Bool) (targets : List String) =>
        s!"build old={old} targets={targets}")
      (Spec.switch "old" (some 'o') "Rebuild only modified modules")
      (Spec.many (Spec.arg "targets" "Targets to build" Param.str)))
    (description := "build targets")

private def queryCommand : Command String :=
  Argus.cmd "query"
    (Spec.map2 (fun (jobs : Nat) (rest : Bool × Bool × List String) =>
        s!"query jobs={jobs} json={rest.1} text={rest.2.1} targets={rest.2.2}")
      (Spec.flag "jobs" (some 'j') "Worker count" Param.nat)
      (Spec.map2 (fun (json : Bool) (rest : Bool × List String) => (json, rest.1, rest.2))
        (Spec.switch "json" (some 'J') "Output JSON-formatted results")
        (Spec.map2 (fun (text : Bool) (targets : List String) => (text, targets))
          (Spec.switch "text" none "Output plain-text results")
          (Spec.many (Spec.arg "targets" "Targets to query" Param.str)))))
    (description :=
      "build targets and output results while preserving independent diagnostics for every target")

private def inspectCommand : Command String :=
  Argus.cmd "inspect"
    (Spec.map (fun (file : String) => s!"inspect {file}")
      (Spec.arg "file" "Lean source file" Param.path))
    (description := "inspect a Lean source file")

private def toolOptions :=
  Spec.map (fun (_ : Bool × Bool) => ())
    (Spec.map2 (fun (verbose : Bool) (dryRun : Bool) => (verbose, dryRun))
      (Spec.switch "verbose" (some 'v') "Enable verbose output")
      (Spec.switch "dry-run" (some 'd') "Preview changes without applying them"))

private def tool : Command String :=
  Argus.groupWithOptions "tool" toolOptions
    [ buildCommand
    , queryCommand
    , inspectCommand
    ]
    (version := some "0.1.0")
    (toolchain := some "Lean version 4.32.2")
    (description := "A typed command-line tool.")

private def rule (title : String) : IO Unit := do
  IO.println ""
  IO.println s!"───── {title} ─────"

private def runAction (action : String) : IO UInt32 := do
  IO.println s!"action: {action}"
  pure 0

private def demo : IO UInt32 := do
  let terminalWidth ← Terminal.terminalWidth
  let width := min terminalWidth TermColor.Layout.defaultWidth
  rule "TOOL HELP"
  IO.print (Help.renderTo RenderTarget.trueColor tool width demoScheme (includeGlobals := true))

  rule "COMMAND-SPECIFIC HELP"
  IO.print
    (Help.renderTo RenderTarget.trueColor queryCommand width demoScheme (includeGlobals := true)
      (commandPath := ["tool", "query"]))

  rule "A SUCCESSFUL PARSE"
  IO.println "argv: query --jobs 4 --json --text build test"
  match tool.run ["query", "--jobs", "4", "--json", "--text", "build", "test"] with
  | .ok action => IO.println s!"{action}"
  | .error errors => for error in errors do IO.println s!"unexpected: {error.message}"

  rule "ACCUMULATED ERRORS"
  IO.println "argv: query --jso --jobs=12x build"
  match tool.run ["query", "--jso", "--jobs=12x", "build"] with
  | .ok action => IO.println s!"unexpected success: {action}"
  | .error errors =>
      IO.print (Text.render RenderTarget.trueColor (Help.renderErrors errors demoScheme))

  rule "BASH COMPLETIONS"
  IO.print (Completions.bash tool)

  rule "ZSH COMPLETIONS"
  IO.print (Completions.zsh tool)

  rule "FISH COMPLETIONS"
  IO.print (Completions.fish tool)

  pure 0

def main (argv : List String) : IO UInt32 :=
  if argv.isEmpty then
    demo
  else
    Term.main tool argv runAction (scheme := demoScheme)
