/-
Copyright (c) 2026 Jonathan Prieto-Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Prieto-Cubides
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

/-- Completion behavior exposed by a typed parameter. -/
inductive CompletionKind where
  | none
  | path
deriving Repr, BEq, Inhabited

/-- A typed parameter: a display name for help, and a decoder for the value. -/
structure Param (α : Type) where
  /-- Shown in help and usage lines: `NAT`, `FILE`, `DURATION`. -/
  typeName : String
  /-- Parser over the value's bytes. `Grip.Parser α` is `GParser fallible α`. -/
  parser : Grip.Parser α
  /-- How interactive frontends should complete this value. -/
  completion : CompletionKind := .none

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
  { typeName := p.typeName, parser := GParser.map f p.parser, completion := p.completion }

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
  { str with typeName := "PATH", completion := .path }

/-! ### More typed values -/

private def labelled {α : Type} {g : Grade} (typeName expected : String)
    (p : GParser g α) : Param α :=
  { typeName, parser := GParser.label expected (ofParser typeName p).parser }

private def byteSliceString (arr : ByteArray) (q q' : Nat) : String :=
  (String.fromUTF8? (arr.extract q q')).getD ""

private def digitsValue (s : String) : Nat :=
  s.toList.foldl (fun n c => n * 10 + (c.toNat - 48)) 0

private def pow10 : Nat → Nat
  | 0 => 1
  | n + 1 => 10 * pow10 n

private def decimalValue (s : String) (multiplier : Nat) : Nat :=
  match s.splitOn "." with
  | [whole] => digitsValue whole * multiplier
  | [whole, fraction] =>
    let scale := pow10 fraction.length
    ((digitsValue whole * scale + digitsValue fraction) * multiplier) / scale
  | _ => 0

private def boolValue (s : String) : Option Bool :=
  match s.toLower with
  | "true" | "yes" | "on" | "1" => some true
  | "false" | "no" | "off" | "0" => some false
  | _ => none

private def rangeValue (s : String) : Option (Nat × Nat) :=
  match s.splitOn ".." with
  | [lo, hi] =>
    let lo := digitsValue lo
    let hi := digitsValue hi
    if lo ≤ hi then some (lo, hi) else none
  | _ => none

private def intCore : GParser conditional Int :=
  GParser.map2
    (fun sign n => if sign == some 45 then -Int.ofNat n else Int.ofNat n)
    (GParser.optional (GParser.oneOf [43, 45])) GParser.nat

/-- An integer: optional leading `-` or `+`, followed by one or more decimal digits. -/
def int : Param Int :=
  labelled "INT" "an integer" intCore

private def boolCore : GParser conditional Bool :=
  GParser.captureWith?
    (fun arr q q' => boolValue (byteSliceString arr q q'))
    (GParser.takeWhile1 Grip.Ascii.isAlphaNum)

/-- A boolean: case-insensitive `true`, `false`, `yes`, `no`, `on`, `off`, `1`, or `0`. -/
def bool : Param Bool :=
  labelled "BOOL" "a boolean" boolCore

private def durationUnit : GParser conditional Nat :=
  GParser.map
    (fun b => if b == 100 then 86400 else if b == 104 then 3600 else if b == 109 then 60 else 1)
    (GParser.oneOf [100, 104, 109, 115])

private def durationPart : GParser conditional Nat :=
  GParser.map2 (fun n unit => n * unit) GParser.nat durationUnit

private def durationCore : GParser conditional Nat :=
  GParser.alt
    (GParser.map (List.foldl (fun total part => total + part) 0)
      (GParser.many1 durationPart))
    GParser.nat

/-- A duration in seconds: a bare number or one or more decimal number/unit parts using `d`,
`h`, `m`, or `s`, such as `2h30m`; returns total seconds. -/
def duration : Param Nat :=
  labelled "DURATION" "a duration in seconds" durationCore

private def bytesScale (name : String) (scale : Nat) : GParser conditional Nat :=
  GParser.map (fun _ => scale) (GParser.string name)

private def bytesUnit : GParser conditional Nat :=
  GParser.alt (bytesScale "Ki" 1024)
    (GParser.alt (bytesScale "Mi" (1024 * 1024))
      (GParser.alt (bytesScale "Gi" (1024 * 1024 * 1024))
        (GParser.alt (bytesScale "Ti" (1024 * 1024 * 1024 * 1024))
          (GParser.alt (bytesScale "k" 1000)
            (GParser.alt (bytesScale "K" 1000)
              (GParser.alt (bytesScale "M" 1000000)
                (GParser.alt (bytesScale "G" 1000000000)
                  (bytesScale "T" 1000000000000))))))))

private def bytesNumber : GParser conditional String :=
  GParser.capture
    (GParser.seqL (GParser.takeWhile1 (fun b => 48 ≤ b && b ≤ 57))
      (GParser.optional
        (GParser.seqR (GParser.ch '.')
          (GParser.takeWhile1 (fun b => 48 ≤ b && b ≤ 57)))))

private def bytesSuffix : GParser conditional Nat :=
  GParser.seqL bytesUnit (GParser.optional (GParser.ch 'B'))

private def bytesCore : GParser conditional Nat :=
  GParser.map2 (fun number scale => decimalValue number (scale.getD 1))
    bytesNumber (GParser.optional bytesSuffix)

/-- A byte count: an integer or decimal number with optional `k`, `K`, `M`, `G`, or `T`
decimal units, or `Ki`, `Mi`, `Gi`, or `Ti` binary units; a trailing `B` is ignored and the
result is returned in bytes. -/
def bytes : Param Nat :=
  labelled "BYTES" "a byte count" bytesCore

private def rangeSyntax : GParser conditional Nat :=
  GParser.seqL GParser.nat
    (GParser.seqR (GParser.seqL (GParser.ch '.') (GParser.ch '.')) GParser.nat)

private def rangeCore : GParser conditional (Nat × Nat) :=
  GParser.captureWith?
    (fun arr q q' => rangeValue (byteSliceString arr q q')) rangeSyntax

/-- A natural-number range `LO..HI`, returned as `(LO, HI)`; it requires `LO ≤ HI`. -/
def range : Param (Nat × Nat) :=
  labelled "RANGE" "an ordered range LO..HI" rangeCore

private def csvElement {α : Type} (p : Param α) : GParser conditional α :=
  GParser.captureWith?
    (fun arr q q' =>
      match p.decode (byteSliceString arr q q') with
      | .ok a => some a
      | .error _ => none)
    (GParser.takeWhile1 (fun b => b != 44))

/-- A comma-separated list of values accepted by `p`; every element is nonempty. -/
def csv {α : Type} (p : Param α) : Param (List α) :=
  labelled "LIST" "a nonempty comma-separated list element"
    (GParser.sepBy (csvElement p) (GParser.ch ','))

private def enumValue {α : Type} : List (String × α) → String → Option α
  | [], _ => none
  | (name, value) :: rest, input => if name == input then some value else enumValue rest input

private def enumCore {α : Type} (choices : List (String × α)) : GParser fallible α :=
  GParser.captureWith?
    (fun arr q q' => enumValue choices (byteSliceString arr q q'))
    (GParser.takeWhile (fun _ => true))

/-- An exact case-sensitive match against the supplied names, returning the associated value;
failure lists all accepted names in its expected-message label. -/
def enum {α : Type} (choices : List (String × α)) : Param α :=
  labelled "ENUM" ("one of " ++ String.intercalate ", " (choices.map (·.1)))
    (enumCore choices)

end Param
end Argus
