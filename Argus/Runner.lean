/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Cubides
-/

import Argus.Spec

/-!
# Argus.Runner: argv to typed values

Two stages.

**Tokenize** splits `List String` into named flags and positionals, handling `--flag`,
`--flag=value`, `--flag value`, `-f`, `-f value`, and the `--` terminator.

**Interpret** walks a `Spec` against those tokens, accumulating every independent error
rather than stopping at the first. `ap` has no data dependency between its sides, so both
run: `tool --jobs=abc --colour=auto` reports the bad `Nat` *and* the unknown flag in one
pass.

This layer is hand-rolled rather than grip-backed. grip runs over `ByteArray`, so using it
here would mean NUL-joining argv and mapping byte offsets back to argv indices, for no
benefit at a workload of roughly ten tokens. grip earns its place one level down, in
`Argus.Param`, where flag *values* are real grammars.
-/

namespace Argus

/-! ### Errors -/

/-- A single failure. `badValue` carries grip's positioned `ParseError`. -/
inductive Err where
  | unknownFlag (given : String) (didYouMean : Option String)
  | missingSubcommand (command : String) (available : List String)
  | unknownSubcommand (given : String) (didYouMean : Option String)
  | missingFlag (long : String)
  | badValue (flag : String) (given : String) (err : Grip.ParseError)
  | missingArg (name : String)
  | unexpectedArg (given : String)
  | flagNeedsValue (long : String)
  | custom (msg : String)
  deriving Inhabited

/-- Render a failure for the terminal. -/
def Err.message : Err → String
  | .unknownFlag g none => s!"unknown flag '{g}'"
  | .unknownFlag g (some d) => s!"unknown flag '{g}'; did you mean '--{d}'?"
  | .missingSubcommand c available =>
    let names := if available.isEmpty then "(none)" else ", ".intercalate available
    s!"missing subcommand for '{c}'; available subcommands: {names}"
  | .unknownSubcommand g none => s!"unknown subcommand '{g}'"
  | .unknownSubcommand g (some d) => s!"unknown subcommand '{g}'; did you mean '{d}'?"
  | .missingFlag l => s!"missing required flag '--{l}'"
  | .badValue f given e =>
    let expected := if e.expected.isEmpty then "" else s!"; expected {", ".intercalate e.expected}"
    s!"invalid value '{given}' for '--{f}' at column {e.pos}{expected}"
  | .missingArg n => s!"missing required argument <{n}>"
  | .unexpectedArg g => s!"unexpected argument '{g}'"
  | .flagNeedsValue l => s!"flag '--{l}' needs a value"
  | .custom m => m

/-! ### Tokenizing -/

/-- argv split into named flags and positionals. `flags` keeps the surface spelling that
produced each entry so error messages can quote what the user actually typed. -/
structure Tokens where
  /-- Long name (without dashes), optional attached value, and the spelling as given. -/
  flags : List (String × Option String × String)
  positionals : List String
  deriving Inhabited

/-- Split `--name=value` into its parts. -/
private def splitEq (s : String) : String × Option String :=
  match s.splitOn "=" with
  | [] => (s, none)
  | [only] => (only, none)
  | name :: rest => (name, some ("=".intercalate rest))

/-- Tokenize argv.

`takesValue` says whether a flag name consumes the following argv element, so both
`--jobs=4` and `--jobs 4` work. The caller derives it from the spec's own metadata —
which is only possible because `Spec` is inspectable, and is the first place that
property pays for itself.

Short flags are recorded under their single-character name; the interpreter resolves
them against the spec's short names. Everything after a bare `--` is positional. -/
def tokenize (takesValue : String → Bool) (argv : List String) : Tokens :=
  go (argv.length + 1) argv { flags := [], positionals := [] }
where
  go : Nat → List String → Tokens → Tokens
  | 0, _, acc => { flags := acc.flags.reverse, positionals := acc.positionals.reverse }
  | _, [], acc => { flags := acc.flags.reverse, positionals := acc.positionals.reverse }
  | _ + 1, "--" :: rest, acc =>
    { flags := acc.flags.reverse, positionals := acc.positionals.reverse ++ rest }
  | fuel + 1, a :: rest, acc =>
    if a.startsWith "--" then
      let (name, val) := splitEq (a.drop 2).toString
      match val with
      | some value => go fuel rest { acc with flags := (name, some value, a) :: acc.flags }
      | none =>
        match rest with
        | v :: more =>
          if takesValue name && !v.startsWith "-" then
            go fuel more { acc with flags := (name, some v, a) :: acc.flags }
          else go fuel (v :: more) { acc with flags := (name, none, a) :: acc.flags }
        | [] => go fuel [] { acc with flags := (name, none, a) :: acc.flags }
    else if a.startsWith "-" && a.length > 1 then
      let name := (a.drop 1).toString
      match rest with
      | v :: more =>
        if takesValue name && !v.startsWith "-" then
          go fuel more { acc with flags := (name, some v, a) :: acc.flags }
        else go fuel (v :: more) { acc with flags := (name, none, a) :: acc.flags }
      | [] => go fuel [] { acc with flags := (name, none, a) :: acc.flags }
    else
      go fuel rest { acc with positionals := a :: acc.positionals }

/-! ### Interpreting -/

/-- Interpreter state: the token pool, shrinking as the spec consumes it. -/
structure St where
  flags : List (String × Option String × String)
  positionals : List String
  errors : List Err
  deriving Inhabited

/-- Levenshtein distance, for "did you mean". Standard row-wise dynamic program:
`prev` is the previous row, `cur` is built left to right taking the best of insertion,
deletion, and substitution. -/
def editDistance (a b : String) : Nat :=
  let bs := b.toList
  let init : List Nat := List.range (bs.length + 1)
  let final := a.toList.foldl (fun prev ac =>
    let first := prev.headD 0 + 1
    let (cur, _, _) := bs.foldl (fun (acc : List Nat × Nat × Nat) bc =>
      let (row, left, j) := acc
      let cost := if ac == bc then 0 else 1
      let insert := left + 1
      let delete := prev.getD (j + 1) 0 + 1
      let substitute := prev.getD j 0 + cost
      let value := min insert (min delete substitute)
      (value :: row, value, j + 1))
      ([first], first, 0)
    cur.reverse) init
  final.getLastD 0

/-- Closest known flag name, when it is close enough to be worth suggesting. -/
def suggest (known : List String) (given : String) : Option String :=
  let scored := known.map (fun k => (editDistance k given, k))
  match scored.foldl (fun best c => if c.1 < best.1 then c else best) (999, "") with
  | (d, k) => if d ≤ 2 && k ≠ "" then some k else none

/-- Look up and remove a flag by long name or short name. -/
private def takeFlag (st : St) (long : String) (short : Option Char) :
    Option (Option String × String) × St :=
  let nameMatches (n : String) : Bool :=
    n == long || (match short with | some c => n == c.toString | none => false)
  match st.flags.findIdx? (fun (n, _, _) => nameMatches n) with
  | none => (none, st)
  | some i =>
    match st.flags[i]? with
    | none => (none, st)
    | some (_, v, spelling) =>
      (some (v, spelling), { st with flags := st.flags.eraseIdx i })

/-- Run a spec against the token pool. Returns `none` when this spec could not be
satisfied; errors are accumulated in the state either way. -/
def interp : {g : Grade} → {α : Type} → Spec g α → St → Option α × St
  | _, _, .const a, st => (some a, st)
  | _, _, .switch l s _, st =>
    match takeFlag st l s with
    | (none, st) => (some false, st)
    | (some _, st) => (some true, st)
  | _, _, .flag l s _ p, st =>
    match takeFlag st l s with
    | (none, st) => (none, { st with errors := .missingFlag l :: st.errors })
    | (some (none, _), st) =>
      (none, { st with errors := .flagNeedsValue l :: st.errors })
    | (some (some v, _), st) =>
      match p.decode v with
      | .ok a => (some a, st)
      | .error e => (none, { st with errors := .badValue l v e :: st.errors })
  | _, _, .arg n _ p, st =>
    match st.positionals with
    | [] => (none, { st with errors := .missingArg n :: st.errors })
    | v :: rest =>
      let st := { st with positionals := rest }
      match p.decode v with
      | .ok a => (some a, st)
      | .error e => (none, { st with errors := .badValue n v e :: st.errors })
  | _, _, .ap f x, st =>
    -- Both sides run, so independent failures are all reported in one pass.
    let (fv, st) := interp f st
    let (xv, st) := interp x st
    match fv, xv with
    | some fv, some xv => (some (fv xv), st)
    | _, _ => (none, st)
  | _, _, .alt x y, st =>
    -- Try the left branch on a snapshot; on failure discard its errors and take the right.
    match interp x st with
    | (some a, st') => (some a, st')
    | (none, _) => interp y st
  | _, _, .opt x, st =>
    match interp x st with
    | (some a, st') => (some (some a), st')
    | (none, _) => (some none, st)
  | _, _, .many x, st =>
    -- The element's type already guarantees it consumes. The interpreter still bounds the
    -- loop by the token count and demands measurable progress, so even a mis-built
    -- element cannot spin. Folding over `List.range` keeps this structurally terminating.
    let fuel := st.flags.length + st.positionals.length + 1
    let (acc, st, _) := (List.range fuel).foldl
      (fun acc _ =>
        let (xs, st, stopped) := acc
        if stopped then (xs, st, true)
        else
          let before := st.flags.length + st.positionals.length
          match interp x st with
          | (some a, st') =>
            if st'.flags.length + st'.positionals.length < before then
              (a :: xs, st', false)
            else (xs, st, true)
          | (none, _) => (xs, st, true))
      ([], st, false)
    (some acc.reverse, st)

/-- Parse argv against a spec. Returns the value, or every error found. -/
def run {g : Grade} {α : Type} (s : Spec g α) (argv : List String) : Except (List Err) α :=
  -- A flag takes a value exactly when its metadata records a type name. Switches do not.
  let valued := s.toMeta.flags.filter (·.typeName.isSome)
  let takesValue (n : String) : Bool :=
    valued.any (fun f => f.long == n || (match f.short with
                                          | some c => c.toString == n
                                          | none => false))
  let ts := tokenize takesValue argv
  let st : St := { flags := ts.flags, positionals := ts.positionals, errors := [] }
  let (v, st) := interp s st
  -- Anything left in the pool was never claimed by the spec. Unclaimed positionals are
  -- as much a user error as unknown flags: `tool a b c` against a one-argument spec used
  -- to silently drop b and c.
  let known := s.flagNames
  let leftoverFlags := st.flags.map (fun (n, _, spelling) =>
    Err.unknownFlag spelling (suggest known n))
  let leftoverArgs := st.positionals.map Err.unexpectedArg
  match v, st.errors.reverse ++ leftoverFlags ++ leftoverArgs with
  | some a, [] => .ok a
  | _, errs => .error (if errs.isEmpty then [Err.custom "parse failed"] else errs)

end Argus
