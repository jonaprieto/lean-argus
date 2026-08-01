# argus — design

Date: 2026-08-01
Status: approved design, not yet implemented
Repo: `lean-argus` (private), namespace `Argus`, package `argus`, Apache-2.0

## Summary

A CLI library for Lean 4, private, built for the author's own tools. It owns the whole
stack: an inspectable command `Spec`, typed value decoders backed by `grip`, an argv
runner backed by `grip`, colored help from the `termcolor` family, and shell completions.

It does **not** depend on `lean4-cli`. See Decision 7.

## Goals

- Parse argv into typed values, with real errors (position, expected set, suggestions).
- Flag *values* are grammars, not strings: `--time=2h30m`, `--range=10..20`,
  `--size=1.5GiB`, `--config='{"a":1}'`.
- Help text and shell completions derived from one inspectable `Spec`, provably
  agreeing with what the parser accepts.
- Colored output through the author's existing `termcolor` stack.
- Dogfood `grip` on a second real workload.

## Non-goals

- Public release or third-party adoption. This is private, for one consumer.
- Interop with `lean4-cli`. Nothing the author owns uses it.
- Beating `clap`/`optparse-applicative` on ergonomics for newcomers.
- A TUI. `termcolor-terminal` already covers live output; `Argus` does not wrap it.

## Architecture

```
                        Argus (namespace)
                              |
      +----------+------------+------------+------------------+
      |          |            |            |                  |
 Argus.Spec  Argus.Param  Argus.Runner  Argus.Help      Argus.Completions
 (graded,    (grip value   (grip argv   (termcolor      (pure Spec walk,
  inspect-    decoders)     parser)      + -layout)      no color)
  able)
      |          |            |            |                  |
      +----------+------------+            |                  |
                 |                         |                  |
          grip (private)             termcolor,          (Spec only)
     Grade / Modality + GParser      termcolor-layout
                 |
        Argus.Properties   — machine-checked laws, no mathlib
```

Dependencies: `grip` (private), `termcolor`, `termcolor-layout`. All three are the
author's own, all pinned by SHA, all on one toolchain.

`Argus.Completions` depends on `Argus.Spec` alone — no color, no IO, pure `String` out.
`Argus.Help` adds `termcolor` and `termcolor-layout` only. `termcolor-widgets` and
`termcolor-terminal` are **not** dependencies; per the termcolor house style, the caller
owns terminal size and output.

## Core types

```lean
namespace Argus

/-- A typed parameter. `parser` is a grip parser over the flag value's bytes. -/
structure Param (α : Type) where
  typeName : String              -- shown in help: "NAT", "DURATION", "FILE"
  parser   : Grip.Parser α       -- abbrev for GParser fallible α

def Param.decode (p : Param α) (s : String) : Except Grip.ParseError α :=
  p.parser.parse s.toUTF8

/-- Grade-indexed, inspectable command spec. `Grade` is grip's, imported unchanged. -/
inductive Spec : Grade → Type → Type 1
  | pure     : α → Spec Grade.pure α
  | switch   : (long : String) → (short : Option Char) → (help : String)
               → Spec flexible Bool
  | flag     : (long : String) → (short : Option Char) → (help : String)
               → Param α → Spec conditional α
  | arg      : (name : String) → (help : String) → Param α → Spec conditional α
  | ap       : Spec g₁ (α → β) → Spec g₂ α → Spec (g₁ * g₂) β
  | alt      : Spec g₁ α → Spec g₂ α → Spec (Grade.choice g₁ g₂) α
  | optional : Spec g α → Spec (Grade.choice g 1) (Option α)
  | many     : Spec ⟨ge, always⟩ α → Spec flexible (List α)
```

`ap` and `alt` compose grades with `Grade.mul` and `Grade.choice` verbatim from
`Grip/Grade.lean`. No new algebra. `Type 1` is forced by `ap` existentially quantifying
the intermediate type, as in any free applicative.

`many` mirrors `GParser.many` (`Grip/Scan.lean:468`): the element spec's type demands
`consumes = always`, so `many (optional f)` is an elaboration error rather than a hang.

## Data flow

```
  argv : List String
      |
      |  Argus.Runner  (grip parser over argv structure)
      v
  raw tokens: flags, values, positionals, subcommand path
      |
      |  Param.decode  (grip parser per flag value)
      v
  Except Errs α

  Spec ──> Argus.Help          (colored, width-parameterised)
       └─> Argus.Completions   (bash / zsh / fish)
```

`Argus.Help.render (s : Spec g α) (width : Nat := 80) : TermColor.Text` — width is a
parameter, not detected. Keeps `Argus.Help` pure and free of `termcolor-terminal`.

## Errors

```lean
inductive Err where
  | unknownFlag (given : String) (didYouMean : Option String)
  | missingFlag (long : String)
  | badValue    (flag : String) (given : String) (err : Grip.ParseError)
  | missingArg  (name : String)
  | custom      (msg : String)

structure Errs where
  errors : List Err
```

Decoding **accumulates** rather than short-circuiting. `ap` has no data dependency
between its sides, so both run and every independent failure is collected:
`mytool --jobs=abc --colour=auto` reports the bad `Nat` *and* the misspelled flag in one
pass.

`badValue` carries grip's `ParseError` (`pos`, `line`, `col`, `expected : List String`),
so `--time=2h3Xm` gets a caret at column 4 with the expected set.

"Did you mean" is edit distance over the flag names reachable from `Spec` — a pure
function, possible only because `Spec` is inspectable data rather than an opaque closure.

Exit codes: `0` success, `1` runtime failure, `2` usage error. Stated explicitly because
`eventb` currently returns `0` on a usage error.

## Testing

**`Argus.Properties`** — machine-checked, no mathlib, matching the `.Properties` pattern
used by `grip`, `termcolor`, `-layout`, `-widgets`, and `-terminal`.

```lean
theorem help_sound (s : Spec g α) (f : String) :
    f ∈ s.flagNames ↔ (Argus.Help.render s).plainText.mentionsFlag f

theorem completion_sound (s : Spec g α) (f : String) :
    f ∈ s.flagNames ↔ f ∈ (Argus.Completions.bash s).offeredWords

theorem run_total (s : Spec g α) (argv : List String) :
    ∃ r, Argus.Runner.run s argv = r
```

`help_sound` and `completion_sound` are the distinctive claims. `clap`'s derive can drift
from `clap_complete`'s output; `optparse-applicative`'s `--help` is a separate rendering
pass that can lie. Here they are theorems, provable because `Spec` is inspectable data.

**Golden tests** — generated completion scripts checked in, diffed on change. Catches
formatting regressions no type can.

**Shell conformance** — every generated script through `bash -n`, `zsh -n`, and fish's
parser in CI. A theorem about which *words* appear says nothing about whether the script
*parses*. Validated in the prototype: generated bash passed `bash -n` and, when sourced,
completed `--` to exactly the five long flags.

**Flag-name validation** — flag names are interpolated into `compgen -W "..."`. A name
containing `$` or a backtick would execute. `Spec` construction must reject flag names
outside `[A-Za-z0-9-]`.

## Build order

Interop-first is dead (Decision 7). Order is now driven by what the author's tools need.

| | Ships |
|---|---|
| v0.1 | `Argus.Spec`, `Argus.Param`, `Argus.Runner`, combinator front door. Parses a real command end to end. |
| v0.2 | `Argus.Help` — colored, width-parameterised. |
| v0.3 | `Argus.Completions` — bash, then zsh and fish. |
| v0.4 | `argus_opts` macro front door as sugar over `Spec`. |
| v0.5 | `Argus.Properties`. |

Dogfood target: migrate `eventb-lean`'s hand-rolled argv parsing (`cli/Cli.lean`, 482
lines) onto argus once v0.2 lands.

**Front door**: v0.1 ships the combinator surface only. It needs no macro machinery,
exposes grades naturally, and suits a single FP-minded consumer. The `argus_opts` macro
is additive sugar producing the same `Spec`, so deferring it breaks nothing.

## Measured constraints

Empirical, on Lean 4.28.0 / 4.33.0-rc1, macOS arm64. These shaped the design.

| Finding | Measurement |
|---|---|
| **No `Lean.Elab` anywhere** | hello-world 2,134,496 bytes; same file plus `import Lean.Elab.Deriving.Basic` → 106,526,656 bytes. 50x from one import of code never executed. |
| `meta import` does not help | 107 MB, identical to a plain import. Requires `module` + `public def main`, and still links everything. |
| Macros are free | A macro emitting a structure plus a companion value from field syntax: 2,134,608 bytes. **+112 bytes.** |
| Lean binaries are standalone | `otool -L` shows only `/usr/lib/libc++.dylib` and `/usr/lib/libSystem.B.dylib`. GMP and the Lean runtime are statically linked. Runs under `env -i`. |
| Startup | 5.27 ms/run vs 2.39 ms fork/exec floor — ~2.9 ms runtime init. |

**Consequence**: a `deriving ParseArgs` handler is impossible — it needs
`Lean.Elab.Deriving`, costing 104 MB in every downstream binary. The `argus_opts` macro
front door replaces it at +112 bytes with near-identical ergonomics.

## Decisions

1. **Own `Spec`, not a borrowed one.** `Cli.ParamType` is `{ name, isValid : String → Bool }`
   — validates, never decodes, cannot say why. `Param` carries a real parser.
2. **One repo, layered `lean_lib` targets.** Not a package family. Matches how `grip`
   splits `Grip` / `grip-props` without five repos and five CI configs.
3. **Grade-indexed `Spec`.** Reuses `Grip.Grade` / `Grip.Modality` (341 lines, zero
   transitive imports). Grades hidden behind the macro front door.
4. **No `deriving`.** Measured 104 MB. Replaced by the `argus_opts` macro.
5. **`termcolor` + `termcolor-layout` only for Help.** `Text.width` is display-cell width;
   `String.length` misaligns CJK and emoji. `-widgets` and `-terminal` are not deps —
   width is a parameter.
6. **grip for `Param` value decoders.** Flag values are real grammars and this is the
   exact gap `isValid : String → Bool` cannot fill. A flag value is a single `String`, so
   `String.toUTF8` feeds `GParser.parse` directly — no NUL-joining, no offset remapping.
   grip's `examples/` (`Json`, `Toml`, `Yaml`, `Sexp`, `Http`) become value decoders free.
6b. **grip for the argv runner too — for uniformity, not speed.** argv is ~10 tokens and
   a few hundred bytes; every implementation parses it in microseconds, so grip's
   benchmark performance (canada.json, 2.1 MB in ~20 ms) is irrelevant here. The reason
   is one parser vocabulary across argv structure and flag values, one error type, and
   grades certifying the option loop rather than only value grammars. If the argv layer
   proves awkward against grip's `ByteArray` interface, a hand-rolled tokenizer feeding
   the same `Tokens` type is an acceptable fallback that changes nothing above it.
7. **Drop `lean4-cli`.** Checked: *none* of the author's repos require it — not
   `lean-termcolor`, `-layout`, `-widgets`, `-terminal`, `eventb-lean`, `grip`, or
   `parser`. It appears in `.lake/packages/` only as a stale leftover. With `argus`
   private, the "one require, zero code changes" adoption ramp has zero consumers. Its
   1778 lines bought interop nobody needs, and `require Cli @ main` bumped the toolchain
   to 4.33.0-rc1 against termcolor's 4.28.0.
8. **Private.** Unblocks depending on `grip` (also private), permits breaking changes
   without deprecation cycles, and allows aggressive toolchain pinning.

### Reversed during design

- **grip dropped, then restored.** Under a decode-only design over `lean4-cli`'s finite
  `Parsed` arrays, grades were decorative — structural recursion on a shrinking array
  terminates for free. Restored once the job was correctly identified as flag *values*,
  where `sepBy` and `many` require `conditional` and a zero-width element is a type error.
- **Interop-first build order, then dropped.** Justified entirely by adoption; invalidated
  when `argus` became private and no repo was found using `lean4-cli`.

## Open questions

1. **Does `grip` stay private?** If it goes public, `argus` could too, and the
   `help_sound` / `completion_sound` theorems become publishable. Not required for v0.1.
2. **Which argv edge cases does v0.1 cover?** Dropping `lean4-cli` means owning `-abc`
   clustering, `--flag=value`, `-j4` vs `-j 4`, and the `--` terminator. Proposal: `--k=v`
   and `--` in v0.1; clustering and attached short values in v0.2. To be confirmed against
   what `eventb` actually needs.
3. **Release pipeline.** No repo the author owns has a `release.yml`. Out of scope here,
   tracked separately: 4-target matrix, `.tar.gz` (never bare binaries — a quarantined
   bare binary dies with SIGKILL; `tar` does not propagate quarantine), `SHA256SUMS`,
   bundled Lean `LICENSES` for the statically-linked LGPL-3.0 GMP.

## Prototype

A working v0.1-shaped prototype exists at
`scratchpad/argus-demo`, built against `lean4-cli` before Decision 7. It proved the
inspectable-spec thesis: one command value fed colored help *and* a valid bash completion
script, 2.8 MB binary, `libc++` + `libSystem` only, generated script passing `bash -n` and
completing correctly when sourced. Its `Help.lean` used `Layout.padRight` and display-cell
width as designed. Superseded by Decision 7, but the layering it validated carries over.
