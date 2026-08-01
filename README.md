# argus

[![Lean 4](https://img.shields.io/badge/Lean%204-library-5f5f5f)](lean-toolchain)
[![License](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)

A command-line library for Lean 4. Flag values are grammars, not strings; help text and
shell completions are derived from the same value the parser runs on, so they cannot
disagree with it.

Private, for the author's own tools.

## Layers

One repo, one `require`, layered `lean_lib` targets. Import only what you need.

```
                        Argus (namespace)
                              |
      +----------+------------+------------+------------------+
      |          |            |            |                  |
 Argus.Spec  Argus.Param  Argus.Runner  Argus.Help      Argus.Completions
 (graded,    (grip value   (argv ->      (termcolor      (pure Spec walk,
  inspect-    decoders)     tokens ->     + -layout)      bash/zsh/fish,
  able)                     typed)                        no color)
      |          |            |            |                  |
      +----------+------------+            |                  |
                 |                         |                  |
          grip (private)             termcolor,          (Spec only)
     Grade / Modality + GParser      termcolor-layout
```

`Argus.Completions` depends on the spec alone — no color, no IO. `Argus.Help` adds
`termcolor` and `termcolor-layout` only. `termcolor-widgets` and `termcolor-terminal` are
not dependencies: help takes `width` as a parameter, so the caller owns terminal size.

## Quick start

```lean
import Argus
open Argus

structure Opts where
  ignoreCase : Bool
  jobs : Nat
  pattern : String
  files : List String

def spec :=
  Spec.seq (Spec.seq (Spec.seq
    (Spec.map Opts.mk (Spec.switch "ignore-case" (some 'i') "Match without regard to case"))
    (Spec.flag "jobs" (some 'j') "Number of worker threads" Param.nat))
    (Spec.arg "PATTERN" "Pattern to search for" Param.str))
    (Spec.many (Spec.arg "FILE" "Files to search" Param.path))

def grepish := Argus.cmd "grepish" spec (version := some "0.1.0")

def main (argv : List String) : IO UInt32 := do
  match grepish.run argv with
  | .ok o => IO.println s!"searching for {o.pattern}"; return 0
  | .error errs =>
    IO.eprint (TermColor.Text.render .ansi16 (Help.renderErrors errs))
    return 2
```

No grade is written by hand. All of them are inferred.

## What it does differently

**Flag values are grammars.** `Param` carries a [grip](https://github.com/jonaprieto/grip)
parser over the value's bytes, so a value can be a duration, a range, a size, or JSON —
not just a string that something later hopes to interpret. Errors are positioned:

```
error: invalid value '12x' for '--jobs' at column 2; expected a natural number
```

**Errors accumulate.** `ap` has no data dependency between its sides, so both run and
every independent failure is reported in one pass:

```
$ grepish --jobs=12x --ignor-case needle
error: invalid value '12x' for '--jobs' at column 2; expected a natural number
error: unknown flag '--ignor-case'; did you mean '--ignore-case'?
```

**A zero-width `many` is a type error.** `Spec.many` requires its element to have
`consumes = always`, mirroring `GParser.many`. In Parsec this is a runtime error; here the
elaborator rejects it:

```
error: Application type mismatch: The argument (Spec.arg "FILE" "input" Param.str).opt
  has type     Spec (conditional.choice 1) (Option String)
  but is expected to have type
               Spec { errors := ?m, consumes := always } ?m
```

**Help and completions are derived, not written.** Both read `Spec.toMeta`, a projection
of the same value the runner interprets. They cannot describe a flag the parser does not
accept.

```
$ grepish
grepish 0.1.0
Search text with an inspectable command line.

USAGE
  grepish [FLAGS] <PATTERN> <FILE>...

FLAGS
-i, --ignore-case  Match without regard to case
-n, --line-number  Prefix matches with line numbers
-j, --jobs NAT     Number of worker threads

ARGS
<PATTERN> STRING  Pattern to search for
<FILE>... PATH    Files to search
```

Alignment uses display-cell width, not `String.length`, so descriptions containing CJK or
emoji still line up.

## Completions

`Completions.bash`, `.zsh`, and `.fish` are pure `Command → String`. Flag names are
filtered through `isSafeName` before interpolation, so a malformed spec produces a smaller
script rather than one that executes when sourced; `Completions.validate` reports what was
dropped.

```sh
$ grepish --completions bash > /etc/bash_completion.d/grepish
```

## Build

```sh
lake build          # library
lake build tests    # assertion-based test runner, no framework
lake exe tests
lake exe demo       # one Command value -> help, parses, three completion scripts
```

## Design

See [docs/superpowers/specs/2026-08-01-argus-design.md](docs/superpowers/specs/2026-08-01-argus-design.md)
for the full design, including the measured constraint that shaped it: a single
`import Lean.Elab` costs about 104 MB in every downstream binary, which is why the planned
`argus_opts` front door is a macro rather than a `deriving` handler.

## License

Apache-2.0.
