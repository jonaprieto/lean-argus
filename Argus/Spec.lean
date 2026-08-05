/-
Copyright (c) 2026 Jonathan Prieto-Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Prieto-Cubides
-/

import Argus.Param

/-!
# Argus.Spec: the inspectable, graded command description

`Spec g α` describes how to build an `α` from argv, and carries a `Grade` (grip's,
imported unchanged) tracking whether it may error and whether it must consume.

Two properties matter:

* **Inspectable.** `Spec.meta` projects a `Meta` of plain data. Help and completions are
  computed from that projection rather than written alongside the parser, so they cannot
  drift out of agreement with what is accepted. That is what makes `help_sound` and
  `completion_sound` provable rather than aspirational.
* **Graded.** `many` requires its element to have `consumes = always`, mirroring
  `GParser.many`. `many (optional f)` is an elaboration error, not a runtime hang.

Grades compose with `Grade.mul` and `Grade.choice` verbatim from `Grip/Grade.lean`;
this module introduces no new algebra.
-/

namespace Argus

open Grip

/-! ### Erased metadata

The projection every consumer other than the runner reads. Plain data, `BEq`, `Repr`.
-/

/-- One flag, with its type erased. `typeName` is `none` for a switch. -/
structure FlagInfo where
  long : String
  short : Option Char
  help : String
  typeName : Option String
  deriving Repr, BEq, Inhabited

/-- One positional argument, with its type erased. -/
structure ArgInfo where
  name : String
  help : String
  typeName : String
  variadic : Bool
  deriving Repr, BEq, Inhabited

/-- Everything help and completions need. Derived from a `Spec`, never written by hand. -/
structure Meta where
  flags : List FlagInfo
  args : List ArgInfo
  deriving Repr, BEq, Inhabited

instance : Append Meta where
  append a b := { flags := a.flags ++ b.flags, args := a.args ++ b.args }

/-- The empty metadata; identity for `++`. -/
def Meta.empty : Meta := { flags := [], args := [] }

/-! ### The spec -/

/-- Grade-indexed command spec. `Type 1` is forced by `ap` existentially quantifying its
intermediate type, as in any free applicative. -/
inductive Spec : Grade → Type → Type 1 where
  /-- A constant. Consumes nothing, cannot fail. -/
  | const {α : Type} (a : α) : Spec 1 α
  /-- A boolean flag taking no value. Absent means `false`, so it cannot fail. -/
  | switch (long : String) (short : Option Char) (help : String) : Spec flexible Bool
  /-- A flag taking a value, decoded by `Param`. -/
  | flag {α : Type} (long : String) (short : Option Char) (help : String)
      (p : Param α) : Spec conditional α
  /-- A positional argument. -/
  | arg {α : Type} (name : String) (help : String) (p : Param α) : Spec conditional α
  /-- Applicative application. Grades multiply. -/
  | ap {α β : Type} {g₁ g₂ : Grade} (f : Spec g₁ (α → β)) (x : Spec g₂ α) :
      Spec (g₁ * g₂) β
  /-- Ordered choice. Grades combine by `Grade.choice`. -/
  | alt {α : Type} {g₁ g₂ : Grade} (x : Spec g₁ α) (y : Spec g₂ α) :
      Spec (Grade.choice g₁ g₂) α
  /-- Zero or one. -/
  | opt {α : Type} {g : Grade} (x : Spec g α) : Spec (Grade.choice g 1) (Option α)
  /-- Zero or more. The element **must** consume, so a zero-width element is rejected by
  the elaborator rather than looping at runtime. -/
  | many {α : Type} {ge : Modality} (x : Spec ⟨ge, Modality.always⟩ α) :
      Spec flexible (List α)

namespace Spec

variable {α β : Type} {g g₁ g₂ : Grade}

/-- Project the erased metadata. Help and completions read only this. -/
def toMeta : {g : Grade} → {α : Type} → Spec g α → Meta
  | _, _, .const _ => Meta.empty
  | _, _, .switch l s h => { flags := [⟨l, s, h, none⟩], args := [] }
  | _, _, .flag l s h p => { flags := [⟨l, s, h, some p.typeName⟩], args := [] }
  | _, _, .arg n h p => { flags := [], args := [⟨n, h, p.typeName, false⟩] }
  | _, _, .ap f x => toMeta f ++ toMeta x
  | _, _, .alt x y => toMeta x ++ toMeta y
  | _, _, .opt x => toMeta x
  | _, _, .many x =>
    let m := toMeta x
    { flags := m.flags, args := m.args.map ({ · with variadic := true }) }

/-- Every long flag name reachable from this spec. -/
def flagNames (s : Spec g α) : List String :=
  s.toMeta.flags.map (·.long)

/-- Every short flag name reachable from this spec. -/
def shortNames (s : Spec g α) : List Char :=
  s.toMeta.flags.filterMap (·.short)

/-! ### Combinator surface

The v0.1 front door. Grades are inferred; a user writing these never spells one out,
but a mistake like `many (opt p)` still fails to elaborate.
-/

/-- Lift a pure value. -/
@[inline] def pure' (a : α) : Spec 1 α := .const a

/-- Map over a spec. -/
@[inline] def map (f : α → β) (x : Spec g α) : Spec (1 * g) β :=
  .ap (.const f) x

/-- Applicative application. -/
@[inline] def seq (f : Spec g₁ (α → β)) (x : Spec g₂ α) : Spec (g₁ * g₂) β :=
  .ap f x

/-- Lift a binary function over two specs. -/
@[inline] def map2 {γ : Type} (f : α → β → γ) (x : Spec g₁ α) (y : Spec g₂ β) :
    Spec (1 * g₁ * g₂) γ :=
  .ap (.ap (.const f) x) y

@[inherit_doc] infixl:60 " <*> " => Spec.seq
@[inherit_doc] infixl:65 " <|> " => Spec.alt

end Spec
end Argus
