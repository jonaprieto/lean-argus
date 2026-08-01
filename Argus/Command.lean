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

/-- A named command wrapping a spec. -/
structure Command (g : Grade) (α : Type) where
  name : String
  version : Option String := none
  description : String := ""
  spec : Spec g α

/-- Build a command. Prefer this over the structure literal: the grade is inferred from
the spec, so callers never write one. -/
def cmd {g : Grade} {α : Type} (name : String) (spec : Spec g α)
    (version : Option String := none) (description : String := "") : Command g α :=
  { name, version, description, spec }

namespace Command

variable {g : Grade} {α : Type}

/-- Parse argv against this command's spec. -/
def run (c : Command g α) (argv : List String) : Except (List Err) α :=
  Argus.run c.spec argv

/-- The command's erased metadata. -/
def toMeta (c : Command g α) : Meta := c.spec.toMeta

/-- Flag names a shell should offer, long form. -/
def flagNames (c : Command g α) : List String := c.spec.flagNames

/-- A `USAGE` line derived from the metadata. -/
def usageLine (c : Command g α) : String :=
  let m := c.toMeta
  let flags := if m.flags.isEmpty then "" else " [FLAGS]"
  let args := m.args.foldl (fun acc a =>
    acc ++ " <" ++ a.name ++ ">" ++ (if a.variadic then "..." else "")) ""
  c.name ++ flags ++ args

end Command
end Argus
