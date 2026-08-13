# argus

[![CI](https://github.com/jonaprieto/lean-argus/actions/workflows/ci.yml/badge.svg)](https://github.com/jonaprieto/lean-argus/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/jonaprieto/lean-argus?display_name=tag&sort=semver)](https://github.com/jonaprieto/lean-argus/releases)
[![Lean 4](https://img.shields.io/badge/Lean%204-v4.33.0-6f42c1)](lean-toolchain)
[![Docs](https://img.shields.io/badge/docs-GitHub%20Pages-4c8bf5)](https://jonaprieto.github.io/lean-argus/)
[![License](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)

Typed command-line parsing for Lean 4. Flag values are Grip grammars; help text and shell
completions are derived from the same command specification.

## Quick start

```lean
import Argus
import Argus.Term
open Argus

argus_opts Opts where
  ignoreCase : Bool        := Spec.switch "ignore-case" (some 'i') "Ignore case";
  jobs       : Nat         := Spec.flag "jobs" (some 'j') "Worker threads" Param.nat;
  timeout    : Nat         := Spec.flag "timeout" none "Give up after" Param.duration;
  files      : List String := Spec.many (Spec.arg "FILE" "Files to search" Param.path)

def grepish := Argus.cmd "grepish" Opts.spec (version := some "0.1.0")

def main (argv : List String) : IO UInt32 :=
  Argus.Term.main grepish argv fun o => do
    IO.println s!"{o.jobs} workers, {o.timeout}s budget, {o.files.length} files"
    return 0
```

`Argus.Term.main` handles `--help`, `--version`, completions, terminal width, `NO_COLOR`, and
exit codes. `Argus.Completions` remains pure; `Argus.Help` renders styled help; `Argus.Term` is
the opt-in terminal layer.

## Features

- leaf and nested subcommands;
- typed flags, arguments, repetitions, enums, ranges, durations, bytes, and CSV values;
- accumulated usage errors with source locations inside flag values;
- bash, zsh, and fish completions;
- separate `Argus.Properties` laws and executable tests.

## Build

```sh
lake build Argus Argus.Term Argus.Properties demo tests readme
lake exe demo
lake exe tests
```

## Related projects

Built on [`grip`](https://github.com/jonaprieto/lean-grip),
[`termcolor`](https://github.com/jonaprieto/lean-termcolor), and
[`termcolor-terminal`](https://github.com/jonaprieto/lean-termcolor-terminal).

## License

Apache-2.0.
