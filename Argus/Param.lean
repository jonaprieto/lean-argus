/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Cubides
-/

import Grip

/-!
# Argus.Param: typed flag-value decoders

A flag *value* is where the real grammar lives: `--time=2h30m`, `--range=10..20`,
`--size=1.5GiB`, `--config='{"a":1}'`. `Param α` pairs a display name with a grip parser
over that value's bytes.

A value is a single `String`, so `String.toUTF8` feeds `GParser.parse` directly: no
NUL-joining across argv, no offset remapping, and a failure's `ParseError` position is a
column *within that value*. `--time=2h3Xm` points at column 4.

Grades are load-bearing here. Value grammars use `sepBy`/`many`, which grip types as
requiring `conditional`, so a repetition built over a zero-width element is an
elaboration error rather than a hang.
-/

namespace Argus

open Grip

variable {α β : Type} {g : Grade}

/-- A typed parameter: a display name for help, and a decoder for the value. -/
structure Param (α : Type) where
  /-- Shown in help and usage lines: `NAT`, `FILE`, `DURATION`. -/
  typeName : String
  /-- Parser over the value's bytes. `Grip.Parser α` is `GParser fallible α`. -/
  parser : Grip.Parser α

namespace Param

/-- Decode one flag value. Errors carry grip's positioned `ParseError`
(`pos`, `line`, `col`, `expected`). -/
def decode (p : Param α) (s : String) : Except Grip.ParseError α :=
  p.parser.parse s.toUTF8

/-- Build a `Param` from any graded parser, requiring it to consume the whole value.
The `eof` is what makes `--jobs=4x` a failure rather than a silent `4`. -/
def ofParser (typeName : String) (p : GParser g α) : Param α :=
  { typeName, parser := (GParser.seqL p GParser.eof).weakenFallible }

/-- Rename a parameter's displayed type without changing how it decodes. -/
def named (typeName : String) (p : Param α) : Param α :=
  { p with typeName }

/-- Post-process a decoded value. -/
def map (f : α → β) (p : Param α) : Param β :=
  { typeName := p.typeName, parser := GParser.map f p.parser }

/-! ### Primitives -/

/-- Any string, taken whole. Never fails. -/
def str : Param String where
  typeName := "STRING"
  parser := (GParser.capture (GParser.takeWhile (fun _ => true))).weakenFallible

/-- A natural number.

The label wraps the *whole* parser including the `eof`, so `--jobs=12x` reports
"expected a natural number" rather than grip's internal "expected end of input". -/
def nat : Param Nat where
  typeName := "NAT"
  parser :=
    (GParser.label "a natural number"
      (GParser.seqL GParser.nat GParser.eof)).weakenFallible

/-- A filesystem path. Decodes like `str`; the distinct `typeName` is what lets
completions emit `compgen -f` for this parameter. -/
def path : Param String :=
  named "PATH" str

end Param
end Argus
