/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Cubides
-/

import Argus
import Argus.Term

/-!
# argus demo

One `Command` value drives everything: parsing, structured help, and three shell completion
scripts. The command list below is deliberately broad so the demo exercises the whole surface.
-/

open Argus
open TermColor

private def demoScheme : ColorScheme := ColorScheme.catppuccin

private def newCommand : Command String :=
  Argus.cmd "new"
    (Spec.map2 (fun (name : String) (temp : String) => s!"new {name} {temp}")
      (Spec.arg "name" "Package name" Param.str)
      (Spec.arg "temp" "Package template" Param.str))
    (description := "create a Lean package in a new directory")

private def initCommand : Command String :=
  Argus.cmd "init"
    (Spec.map2 (fun (name : String) (temp : String) => s!"init {name} {temp}")
      (Spec.arg "name" "Package name" Param.str)
      (Spec.arg "temp" "Package template" Param.str))
    (description := "create a Lean package in the current directory")

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
    (description := "build targets and output results")

private def exeCommand : Command String :=
  Argus.cmd "exe"
    (Spec.map2 (fun (exe : String) (args : List String) => s!"exe {exe} args={args}")
      (Spec.arg "exe" "Executable name" Param.str)
      (Spec.many (Spec.arg "args" "Arguments for the executable" Param.str)))
    (description := "build an exe and run it in the tool's environment")

private def checkBuildCommand : Command String :=
  Argus.cmd "check-build" (Spec.const "check-build")
    (description := "check configured build targets")

private def testCommand : Command String :=
  Argus.cmd "test" (Spec.const "test")
    (description := "run package tests")

private def checkTestCommand : Command String :=
  Argus.cmd "check-test" (Spec.const "check-test")
    (description := "check for a test driver")

private def lintCommand : Command String :=
  Argus.cmd "lint" (Spec.const "lint")
    (description := "lint the package")

private def checkLintCommand : Command String :=
  Argus.cmd "check-lint" (Spec.const "check-lint")
    (description := "check for a lint driver")

private def cleanCommand : Command String :=
  Argus.cmd "clean" (Spec.const "clean")
    (description := "remove build outputs")

private def shakeCommand : Command String :=
  Argus.cmd "shake" (Spec.const "shake")
    (description := "minimize imports in source files")

private def envCommand : Command String :=
  Argus.cmd "env"
    (Spec.map2 (fun (cmd : String) (args : List String) => s!"env {cmd} args={args}")
      (Spec.arg "cmd" "Command to execute" Param.str)
      (Spec.many (Spec.arg "args" "Command arguments" Param.str)))
    (description := "execute a command in the tool's environment")

private def leanCommand : Command String :=
  Argus.cmd "lean"
    (Spec.map (fun (file : String) => s!"lean {file}")
      (Spec.arg "file" "Lean source file" Param.path))
    (description := "elaborate a Lean file in the tool's context")

private def updateCommand : Command String :=
  Argus.cmd "update" (Spec.const "update")
    (description := "update dependencies and the manifest")

private def packCommand : Command String :=
  Argus.cmd "pack" (Spec.const "pack")
    (description := "archive build artifacts")

private def unpackCommand : Command String :=
  Argus.cmd "unpack" (Spec.const "unpack")
    (description := "unpack build artifacts")

private def uploadCommand : Command String :=
  Argus.cmd "upload"
    (Spec.map (fun (tag : String) => s!"upload {tag}")
      (Spec.arg "tag" "GitHub release tag" Param.str))
    (description := "upload build artifacts to a GitHub release")

private def cacheCommand : Command String :=
  Argus.cmd "cache" (Spec.const "cache")
    (description := "manage the tool cache")

private def scriptCommand : Command String :=
  Argus.cmd "script" (Spec.const "script")
    (description := "manage and run workspace scripts")

private def scriptsCommand : Command String :=
  Argus.cmd "scripts" (Spec.const "scripts")
    (description := "shorthand for `tool script list`")

private def runCommand : Command String :=
  Argus.cmd "run"
    (Spec.map (fun (script : String) => s!"run {script}")
      (Spec.arg "script" "Workspace script" Param.str))
    (description := "shorthand for `tool script run`")

private def translateConfigCommand : Command String :=
  Argus.cmd "translate-config" (Spec.const "translate-config")
    (description := "translate package configuration")

private def serveCommand : Command String :=
  Argus.cmd "serve" (Spec.const "serve")
    (description := "start the Lean language server")

private def tool : Command String :=
  Argus.group "tool"
    [ newCommand
    , initCommand
    , buildCommand
    , queryCommand
    , exeCommand
    , checkBuildCommand
    , testCommand
    , checkTestCommand
    , lintCommand
    , checkLintCommand
    , cleanCommand
    , shakeCommand
    , envCommand
    , leanCommand
    , updateCommand
    , packCommand
    , unpackCommand
    , uploadCommand
    , cacheCommand
    , scriptCommand
    , scriptsCommand
    , runCommand
    , translateConfigCommand
    , serveCommand
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
  rule "TOOL HELP"
  IO.print (Help.renderTo RenderTarget.trueColor tool 100 demoScheme (includeGlobals := true))

  rule "COMMAND-SPECIFIC HELP"
  IO.print
    (Help.renderTo RenderTarget.trueColor queryCommand 80 demoScheme (includeGlobals := true)
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
