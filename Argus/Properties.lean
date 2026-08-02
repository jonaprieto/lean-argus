/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/

import Argus

/-!
# Argus.Properties: machine-checked laws

The metadata completeness theorem below is general: it follows the `Spec` constructors and
proves that structural flag reachability agrees with `Spec.toMeta`. The grade identities are
general. Help, completion, and shell-filtering checks remain executable tests: their current
implementations call opaque runtime string-search primitives, so a kernel proof would require
an unrequested theorem layer or forbidden native evaluation. This module is a separate build
target so consumers do not link proofs.
-/

namespace Argus.Properties

open Argus
open Grip

def reachableFlagNames : {g : Grade} → {α : Type} → Spec g α → List String
  | _, _, .const _ => []
  | _, _, .switch long _ _ => [long]
  | _, _, .flag long _ _ _ => [long]
  | _, _, .arg _ _ _ => []
  | _, _, .ap f x => reachableFlagNames f ++ reachableFlagNames x
  | _, _, .alt x y => reachableFlagNames x ++ reachableFlagNames y
  | _, _, .opt x => reachableFlagNames x
  | _, _, .many x => reachableFlagNames x

theorem reachableFlagNames_eq {g : Grade} {α : Type} (s : Spec g α) :
    reachableFlagNames s = s.flagNames := by
  induction s with
  | const => rfl
  | switch => rfl
  | flag => rfl
  | arg => rfl
  | ap f x ihf ihx =>
    change reachableFlagNames f ++ reachableFlagNames x =
      (f.toMeta.flags ++ x.toMeta.flags).map (·.long)
    rw [List.map_append, ihf, ihx]
    simp [Spec.flagNames]
  | alt x y ihx ihy =>
    change reachableFlagNames x ++ reachableFlagNames y =
      (x.toMeta.flags ++ y.toMeta.flags).map (·.long)
    rw [List.map_append, ihx, ihy]
    simp [Spec.flagNames]
  | opt x ih =>
    change reachableFlagNames x = x.toMeta.flags.map (·.long)
    exact ih
  | many x ih =>
    change reachableFlagNames x = x.toMeta.flags.map (·.long)
    exact ih

theorem toMeta_complete {g : Grade} {α : Type} (s : Spec g α) (long : String) :
    long ∈ reachableFlagNames s → long ∈ s.toMeta.flags.map (·.long) := by
  rw [reachableFlagNames_eq s]
  exact id

theorem grade_mul_one_left (g : Grade) : Grade.mul Grade.pure g = g := by
  cases g with
  | mk errors consumes => cases errors <;> cases consumes <;> rfl

theorem grade_mul_one_right (g : Grade) : Grade.mul g Grade.pure = g := by
  cases g with
  | mk errors consumes => cases errors <;> cases consumes <;> rfl

theorem grade_choice_one_left (g : Grade) : Grade.choice Grade.pure g = Grade.pure := by
  cases g with
  | mk errors consumes => cases errors <;> cases consumes <;> rfl

theorem grade_choice_idempotent (g : Grade) : Grade.choice g g = g := by
  cases g with
  | mk errors consumes => cases errors <;> cases consumes <;> rfl

structure ProofOpts where
  verbose : Bool
  jobs : Nat
  files : List String

def proofSpec :=
  Spec.seq (Spec.seq (Spec.map ProofOpts.mk
    (Spec.switch "verbose" (some 'v') "Chatty output"))
    (Spec.flag "jobs" none "Worker count" Param.nat))
    (Spec.many (Spec.arg "FILE" "Input" Param.path))

def proofCommand : Command ProofOpts := cmd "proof" proofSpec

theorem proof_meta : proofCommand.flagNames = ["verbose", "jobs"] := by
  rfl

end Argus.Properties
