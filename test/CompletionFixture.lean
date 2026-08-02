/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Cubides
-/

import Argus
import Argus.Term

/-!
# Completion fixture

A two-level command tree whose only job is to be a target for the shell-completion check
in CI. Asserting on the generated script's text cannot tell you whether a shell actually
offers the right words; sourcing it and driving `COMP_WORDS` can.
-/

open Argus
inductive A where | b (r : Bool) | l (s : String) | t (n : Nat) deriving Repr
def buildC := Argus.cmd "build"
  (Spec.map A.b (Spec.switch "release" (some 'r') "Optimised")) (description := "Build")
def testC := Argus.cmd "test"
  (Spec.map A.t (Spec.flag "jobs" (some 'j') "Jobs" Param.nat)) (description := "Test")
def leafC := Argus.cmd "leaf"
  (Spec.map A.l (Spec.arg "S" "s" Param.path)) (description := "Leaf")
def innerC := Argus.group "inner" [leafC] (description := "Nested")
def tool := Argus.group "tool" [buildC, testC, innerC] (version := some "1.0")
def main (argv : List String) : IO UInt32 := Term.main tool argv fun a => do
  IO.println s!"{repr a}"; return 0
