/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Cubides
-/

import Argus
import Argus.Term

/-!
# README doc-test

Every code block in README.md, verbatim. If the README drifts from the API this stops
compiling, which is the point: documentation that cannot rot.
-/

open Argus
argus_opts Opts where
  ignoreCase : Bool        := Spec.switch "ignore-case" (some 'i') "Ignore case";
  jobs       : Nat         := Spec.flag "jobs" (some 'j') "Worker threads" Param.nat;
  timeout    : Nat         := Spec.flag "timeout" none "Give up after" Param.duration;
  files      : List String := Spec.many (Spec.arg "FILE" "Files to search" Param.path)
def grepish := Argus.cmd "grepish" Opts.spec (version := some "0.1.0")
inductive Act where
  | build (release : Bool)
  | test  (filter : String)
def tool := Argus.group "tool"
  [ Argus.cmd "build" (Spec.map Act.build (Spec.switch "release" (some 'r') "Optimised"))
      (description := "Build the project")
  , Argus.cmd "test"  (Spec.map Act.test (Spec.arg "FILTER" "Name filter" Param.str))
      (description := "Run the tests") ]
  (version := some "0.1.0")
def main (argv : List String) : IO UInt32 :=
  Argus.Term.main grepish argv fun o => do
    IO.println s!"{o.jobs} workers, {o.timeout}s budget, {o.files.length} files"
    return 0
