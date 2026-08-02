/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Cubides
-/

import Argus.Runner

/-!
# Argus.Command: a named, versioned entry point

A `Spec` describes options. A `Command` adds the identity a help page and a completion
script need: name, version, description.
-/

namespace Argus

mutual
  /-- A named command: either a leaf holding a spec, or a branch holding subcommands. -/
  structure Command (α : Type) where
    name : String
    version : Option String := none
    description : String := ""
    body : Body α

  inductive Body (α : Type) where
    | opts {g : Grade} (spec : Spec g α) : Body α
    | subs (children : List (Command α)) : Body α
end

/-- Build a command. Prefer this over the structure literal: the grade is inferred from
the spec, so callers never write one. -/
def cmd {g : Grade} {α : Type} (name : String) (spec : Spec g α)
    (version : Option String := none) (description : String := "") : Command α :=
  { name, version, description, body := .opts spec }

/-- Build a command group. -/
def group {α : Type} (name : String) (children : List (Command α))
    (version : Option String := none) (description : String := "") : Command α :=
  { name, version, description, body := .subs children }

namespace Command

variable {α : Type}

private def firstPositional : List String → Option (String × List String)
  | [] => none
  | arg :: rest =>
    if arg.startsWith "-" then
      match firstPositional rest with
      | none => none
      | some (name, remaining) => some (name, arg :: remaining)
    else some (arg, rest)

private def suggest (known : List String) (given : String) : Option String :=
  let scored := known.map (fun k => (editDistance k given, k))
  match scored.foldl (fun best c => if c.1 < best.1 then c else best) (999, "") with
  | (d, k) => if d ≤ 2 && k ≠ "" then some k else none

/-- Parse argv against this command's spec. -/
partial def run (c : Command α) (argv : List String) : Except (List Err) α :=
  match c.body with
  | .opts spec => Argus.run spec argv
  | .subs children =>
    let available := children.map (·.name)
    match firstPositional argv with
    | none => .error [.missingSubcommand c.name available]
    | some (given, remaining) =>
      match children.find? (·.name == given) with
      | some child => run child remaining
      | none => .error [.unknownSubcommand given (suggest available given)]

/-- Follow subcommand names as far as they match, returning the deepest command reached.

Flags are stepped over, so `tool --verbose build --help` still resolves to `build`. An
unrecognised name stops the walk and yields the last good command, which is what a user
asking for help after a typo should see. -/
partial def resolve (c : Command α) : List String → Command α
  | [] => c
  | a :: rest =>
    if a.startsWith "-" then resolve c rest
    else
      match c.body with
      | .opts _ => c
      | .subs children =>
        match children.find? (·.name == a) with
        | some child => resolve child rest
        | none => c

/-- The command's erased metadata. -/
def toMeta (c : Command α) : Meta :=
  match c.body with
  | .opts spec => spec.toMeta
  | .subs _ => Meta.empty

/-- Flag names a shell should offer, long form. -/
def flagNames (c : Command α) : List String := c.toMeta.flags.map (·.long)

/-- A `USAGE` line derived from the metadata. -/
def usageLine (c : Command α) : String :=
  match c.body with
  | .subs _ => c.name ++ " <SUBCOMMAND>"
  | .opts _ =>
    let m := c.toMeta
    let flags := if m.flags.isEmpty then "" else " [FLAGS]"
    let args := m.args.foldl (fun acc a =>
      acc ++ " <" ++ a.name ++ ">" ++ (if a.variadic then "..." else "")) ""
    c.name ++ flags ++ args

end Command
end Argus
