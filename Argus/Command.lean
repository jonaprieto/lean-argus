/-
Copyright (c) 2026 Jonathan Prieto-Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Prieto-Cubides
-/

import Argus.Runner

/-!
# Argus.Command: a named, versioned entry point

A `Spec` describes options. A `Command` adds the identity a help page and a completion
script need: name, version, description, optional toolchain context, and shared group options.
-/

namespace Argus

abbrev GlobalSpec := Sigma fun g => Spec g Unit

mutual
  /-- A named command: either a leaf holding a spec, or a branch holding subcommands. -/
  structure Command (α : Type) where
    name : String
    version : Option String := none
    description : String := ""
    toolchain : Option String := none
    globalOptions : Option GlobalSpec := none
    body : Body α
    /-- Runnable examples shown by frontend help renderers. -/
    examples : List String := []

  inductive Body (α : Type) where
    | opts {g : Grade} (spec : Spec g α) : Body α
    | subs (children : List (Command α)) : Body α
end

/-- Build a command. Prefer this over the structure literal: the grade is inferred from
the spec, so callers never write one. -/
def cmd {g : Grade} {α : Type} (name : String) (spec : Spec g α)
    (version : Option String := none) (description : String := "")
    (toolchain : Option String := none) (examples : List String := []) : Command α :=
  { name, version, description, toolchain, globalOptions := none, body := .opts spec, examples }

/-- Build a command group. -/
def group {α : Type} (name : String) (children : List (Command α))
    (version : Option String := none) (description : String := "")
    (toolchain : Option String := none) (examples : List String := []) : Command α :=
  { name, version, description, toolchain, globalOptions := none, body := .subs children, examples }

/-- Build a command group with options shared by every subcommand. The option value is parsed
and discarded; child commands still produce the group's result. -/
def groupWithOptions {g : Grade} {α : Type} (name : String) (options : Spec g Unit)
    (children : List (Command α)) (version : Option String := none)
    (description : String := "") (toolchain : Option String := none)
    (examples : List String := []) : Command α :=
  { name, version, description, toolchain,
    globalOptions := some ⟨g, options⟩, body := .subs children, examples }

namespace Command

variable {α : Type}

private def globalFlagTakesValue (arg : String) : Bool :=
  arg == "--completions" || arg.startsWith "--completions="

private def groupFlagTakesValue (c : Command α) (arg : String) : Bool :=
  globalFlagTakesValue arg ||
    match c.globalOptions with
    | none => false
    | some ⟨_, spec⟩ => spec.toMeta.flags.any fun f =>
        f.typeName.isSome && (f.long == arg.drop 2 ||
          match f.short with
          | some ch => ch.toString == arg.drop 1
          | none => false)

private def splitSubcommand (c : Command α) (argv : List String) :
    Option (List String × String × List String) :=
  let rec go : Nat → List String → List String → Option (List String × String × List String)
    | 0, _, _ => none
    | _, [], _ => none
    | _ + 1, "--" :: rest, before =>
      match rest with
      | [] => none
      | name :: remaining => some (before.reverse, name, remaining)
    | fuel + 1, arg :: rest, before =>
      if arg.startsWith "-" then
        if c.groupFlagTakesValue arg then
          match rest with
          | value :: remaining => go fuel remaining (value :: arg :: before)
          | [] => go fuel [] (arg :: before)
        else go fuel rest (arg :: before)
      else some (before.reverse, arg, rest)
  go (argv.length + 1) argv []

/-- Parse argv against this command's spec. -/
def run (c : Command α) (argv : List String) : Except (List Err) α :=
  let rec go : Nat → Command α → List String → Except (List Err) α
    | 0, _, _ => .error [.custom "command nesting exceeded"]
    | fuel + 1, c, argv =>
      match c.body with
      | .opts spec => Argus.run spec argv
      | .subs children =>
        let available := children.map (·.name)
        match c.splitSubcommand argv with
        | none => .error [.missingSubcommand c.name available]
        | some (before, given, remaining) =>
          let dispatch := fun childArgv =>
            match children.find? (·.name == given) with
            | some child => go fuel child childArgv
            | none => .error [.unknownSubcommand given (suggest available given)]
          match c.globalOptions with
          | none => dispatch (before ++ remaining)
          | some ⟨_, spec⟩ =>
            match Argus.run spec before with
            | .error errors => .error errors
            | .ok _ => dispatch remaining
  go (argv.length + 1) c argv

/-- Follow subcommand names as far as they match, returning the deepest command reached.

Flags are stepped over, so `tool --verbose build --help` still resolves to `build`. An
unrecognised name stops the walk and yields the last good command, which is what a user
asking for help after a typo should see. -/
def resolvePath (c : Command α) (argv : List String) : List String × Command α :=
  let rec go : Nat → Command α → List String → List String → List String × Command α
    | 0, c, _, path => (path, c)
    | _, c, [], path => (path, c)
    | fuel + 1, c, a :: rest, path =>
      if a.startsWith "-" then
        let remaining := if c.groupFlagTakesValue a then rest.drop 1 else rest
        go fuel c remaining path
      else
        match c.body with
        | .opts _ => (path, c)
        | .subs children =>
          match children.find? (·.name == a) with
          | some child => go fuel child rest (path ++ [child.name])
          | none => (path, c)
  go (argv.length + 1) c argv [c.name]

/-- Follow subcommand names as far as they match, returning the deepest command reached. -/
def resolve (c : Command α) (argv : List String) : Command α :=
  (c.resolvePath argv).2

/-- The command's erased metadata. -/
def toMeta (c : Command α) : Meta :=
  match c.body with
  | .opts spec => spec.toMeta
  | .subs _ => match c.globalOptions with
    | none => Meta.empty
    | some ⟨_, spec⟩ => spec.toMeta

/-- Flag names a shell should offer, long form. -/
def flagNames (c : Command α) : List String := c.toMeta.flags.map (·.long)

/-- A command synopsis derived from the metadata. -/
def usageLine (c : Command α) : String :=
  match c.body with
  | .subs _ => c.name ++ " [OPTIONS] <COMMAND>"
  | .opts _ =>
    let m := c.toMeta
    let flags := if m.flags.isEmpty then "" else " [OPTIONS]"
    let args := m.args.foldl (fun acc a => acc ++ " " ++ ArgInfo.usage a) ""
    c.name ++ flags ++ args

end Command
end Argus
