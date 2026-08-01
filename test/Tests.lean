/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Cubides
-/

import Argus

/-!
# Argus test runner

Assertion-based, no framework. Each check returns `none` on success or `some message`
on failure; `main` prints failures and exits non-zero.
-/

open Argus

private def check (name : String) (ok : Bool) : Option String :=
  if ok then none else some name

private def hasSubstr (hay needle : String) : Bool :=
  (hay.splitOn needle).length > 1

/-! ### Param -/

private def paramChecks : List (Option String) :=
  [ check "nat decodes 42"
      (Param.nat.decode "42" matches .ok 42)
  , check "nat rejects trailing junk (eof enforced)"
      (Param.nat.decode "42x" matches .error _)
  , check "nat rejects empty"
      (Param.nat.decode "" matches .error _)
  , check "nat rejects non-numeric"
      (Param.nat.decode "abc" matches .error _)
  , check "str takes the whole value"
      (Param.str.decode "hello world" matches .ok "hello world")
  , check "str accepts empty"
      (Param.str.decode "" matches .ok "")
  , check "str keeps '=' in the value"
      (Param.str.decode "a=b" matches .ok "a=b")
  , check "path decodes like str but is named PATH"
      (Param.path.typeName == "PATH" && Param.path.decode "/tmp/x" matches .ok "/tmp/x")
  , check "map post-processes"
      ((Param.nat.map (· * 2)).decode "21" matches .ok 42)
  ]

/-- Error positions are columns within the value, not offsets into a joined argv. -/
private def errorPositionCheck : Option String :=
  match Param.nat.decode "12x" with
  | .error e => check "error column points inside the value" (e.pos == 2)
  | .ok _ => some "expected a failure on 12x"

/-! ### Edit distance (backs "did you mean") -/

private def editDistanceChecks : List (Option String) :=
  [ check "identical strings" (editDistance "abc" "abc" == 0)
  , check "one deletion" (editDistance "jobs" "jbs" == 1)
  , check "one deletion in a longer name" (editDistance "ignore-case" "ignor-case" == 1)
  , check "classic kitten/sitting" (editDistance "kitten" "sitting" == 3)
  , check "empty against non-empty" (editDistance "" "abc" == 3)
  , check "non-empty against empty" (editDistance "abc" "" == 3)
  , check "symmetric" (editDistance "flaw" "lawn" == editDistance "lawn" "flaw")
  ]

/-! ### A realistic spec -/

structure Opts where
  ignoreCase : Bool
  jobs : Nat
  pattern : String
  files : List String
  deriving Repr, BEq

/-- `grepish [-i] --jobs=N PATTERN FILE...` built from the combinator front door.
No grade is written by hand; all of them are inferred. -/
def optsSpec :=
  Spec.seq (Spec.seq (Spec.seq
    (Spec.map Opts.mk (Spec.switch "ignore-case" (some 'i') "Match without regard to case"))
    (Spec.flag "jobs" (some 'j') "Worker count" Param.nat))
    (Spec.arg "PATTERN" "Pattern to search for" Param.str))
    (Spec.many (Spec.arg "FILE" "Files to search" Param.str))

private def okIs (argv : List String) (expected : Opts) : Bool :=
  match Argus.run optsSpec argv with
  | .ok o => o == expected
  | .error _ => false

private def errCount (argv : List String) : Nat :=
  match Argus.run optsSpec argv with
  | .ok _ => 0
  | .error es => es.length

private def firstErr (argv : List String) : String :=
  match Argus.run optsSpec argv with
  | .ok _ => "<no error>"
  | .error es => (es.head?.map Err.message).getD "<empty>"

/-! ### Spec metadata -/

private def metaChecks : List (Option String) :=
  [ check "toMeta lists both flags"
      (optsSpec.flagNames == ["ignore-case", "jobs"])
  , check "toMeta lists both short names"
      (optsSpec.shortNames == ['i', 'j'])
  , check "switch has no type name, flag does"
      (optsSpec.toMeta.flags.map (·.typeName) == [none, some "NAT"])
  , check "toMeta lists positional args in order"
      (optsSpec.toMeta.args.map (·.name) == ["PATTERN", "FILE"])
  , check "many marks its argument variadic"
      (optsSpec.toMeta.args.map (·.variadic) == [false, true])
  ]

/-! ### Runner -/

private def runnerChecks : List (Option String) :=
  [ check "attached value: --jobs=2"
      (okIs ["-i", "--jobs=2", "needle", "a.txt", "b.txt"]
        ⟨true, 2, "needle", ["a.txt", "b.txt"]⟩)
  , check "separate value: --jobs 2"
      (okIs ["--jobs", "2", "needle"] ⟨false, 2, "needle", []⟩)
  , check "short separate value: -j 2"
      (okIs ["-j", "2", "needle"] ⟨false, 2, "needle", []⟩)
  , check "absent switch is false"
      (okIs ["--jobs=1", "needle"] ⟨false, 1, "needle", []⟩)
  , check "long switch form"
      (okIs ["--ignore-case", "--jobs=1", "needle"] ⟨true, 1, "needle", []⟩)
  , check "many collects zero files"
      (okIs ["--jobs=1", "p"] ⟨false, 1, "p", []⟩)
  , check "many collects several files"
      (okIs ["--jobs=1", "p", "a", "b", "c"] ⟨false, 1, "p", ["a", "b", "c"]⟩)
  , check "-- terminator makes a dash-leading token positional"
      (okIs ["--jobs=1", "p", "--", "-weird.txt"] ⟨false, 1, "p", ["-weird.txt"]⟩)
  , check "missing required flag is an error"
      (errCount ["needle"] == 1)
  , check "missing positional is an error"
      (errCount ["--jobs=1"] == 1)
  , check "bad value is an error"
      (errCount ["--jobs=abc", "needle"] == 1)
  , check "errors accumulate rather than short-circuit"
      (errCount ["--jobs=abc", "--nope=1", "needle"] == 2)
  ]

/-- Message quality: positioned value errors and edit-distance suggestions. -/
private def messageChecks : List (Option String) :=
  [ check "bad value reports the column inside the value"
      (hasSubstr (firstErr ["--jobs=12x", "needle"]) "at column 2")
  , check "bad value names what was expected, not grip internals"
      (hasSubstr (firstErr ["--jobs=12x", "needle"]) "a natural number")
  , check "unknown flag suggests the closest known name"
      ((firstErr ["--jbs=2", "needle", "--jobs=1"]).endsWith "did you mean '--jobs'?")
  , check "unknown flag with no close match makes no suggestion"
      ((firstErr ["--zzzzzzz=2", "needle", "--jobs=1"]).endsWith "unknown flag '--zzzzzzz=2'")
  ]

/-! ### Help rendering -/

private def longCmd :=
  Argus.cmd "demo"
    (Spec.map (fun (b : Bool) => b)
      (Spec.switch "verbose" (some 'v')
        "Emit a great deal of additional detail about every step being taken"))
    (description := "d")

/-- Rendered at 40 columns, the description must wrap, continuation lines must be
indented under the description column, and no line may carry trailing whitespace. -/
private def helpChecks : List (Option String) :=
  let lines := (Help.render longCmd 40).plainText.splitOn "\n"
  let flagLines := lines.filter (fun l => (l.splitOn "--verbose").length > 1)
  let contLines := lines.filter (fun l => (l.splitOn "detail").length > 1)
  [ check "no line has trailing whitespace"
      (lines.all fun l => !l.endsWith " ")
  , check "the long description wraps onto more than one line"
      (flagLines.length == 1 && contLines.length == 1 && flagLines != contLines)
  , check "continuation lines are indented, not flush left"
      (contLines.all fun l => l.startsWith "  ")
  , check "no rendered line exceeds the requested width"
      (lines.all fun l => l.length <= 40)
  ]

def main : IO UInt32 := do
  let results :=
    paramChecks ++ [errorPositionCheck] ++ editDistanceChecks ++ metaChecks
      ++ runnerChecks ++ messageChecks ++ helpChecks
  let failures := results.filterMap id
  if failures.isEmpty then
    IO.println s!"all {results.length} checks passed"
    return 0
  else
    for f in failures do
      IO.eprintln s!"FAIL: {f}"
    IO.eprintln s!"{failures.length} of {results.length} checks failed"
    return 1
