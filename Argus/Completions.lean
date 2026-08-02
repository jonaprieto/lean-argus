/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Cubides
-/

import Argus.Command

/-!
# Argus.Completions: shell completion scripts, derived from the spec

Pure `Command → String`. No color, no IO, no `termcolor` dependency: a caller who wants
completions should not have to link a terminal stack.

Like help, the script is computed from `Spec.toMeta`, so it cannot describe a flag the
parser does not accept. That is `completion_sound`.

## Injection

Flag names are interpolated into shell word lists. A name containing `$`, a backtick, or
a quote would execute when the script is sourced. `isSafeName` is the gate, and every
generator filters through it, so a malformed spec produces a smaller script rather than a
dangerous one. `validate` reports what was dropped.
-/

namespace Argus.Completions

variable {α : Type}

/-- Shell-word-safe: ASCII letters, digits, `-`, `_`. -/
def isSafeName (s : String) : Bool :=
  !s.isEmpty && s.all fun c =>
    c.isAlphanum || c == '-' || c == '_'

/-- Names that would be unsafe to interpolate into a script. Empty means the command is
safe to generate from. -/
def validate (c : Command α) : List String :=
  match c.body with
  | .opts _ => (c.toMeta.flags.map (·.long)).filter (fun n => !isSafeName n)
  | .subs children => children.map (·.name) |>.filter (fun n => !isSafeName n)

/-- Long and short flag words a shell should offer, unsafe names dropped. -/
private def flagWords (c : Command α) : List String :=
  let m := c.toMeta
  let longs := (m.flags.map (·.long)).filter isSafeName |>.map ("--" ++ ·)
  let shorts := m.flags.filterMap (fun f =>
    f.short.bind fun ch =>
      let s := ch.toString
      if isSafeName s then some ("-" ++ s) else none)
  longs ++ shorts

/-- Whether any positional argument is path-typed, so the script should also offer
filenames. `Param.path` is what sets this apart from `Param.str`. -/
private def wantsFiles (c : Command α) : Bool :=
  c.toMeta.args.any (fun a => a.typeName == "PATH")

private def subcommandNames (c : Command α) : List String :=
  match c.body with
  | .opts _ => []
  | .subs children => children.map (·.name) |>.filter isSafeName

private def safeName (c : Command α) : String :=
  String.mk (c.name.toList.map fun ch => if isSafeName ch.toString then ch else '_')

/-! ### bash -/

/-- A bash completion script. Source it, or drop it in `/etc/bash_completion.d`. -/
def bash (c : Command α) : String :=
  let fn := "_" ++ safeName c ++ "_completions"
  let words := match c.body with
    | .opts _ => " ".intercalate (flagWords c)
    | .subs _ => " ".intercalate (subcommandNames c)
  let fileLine :=
    if wantsFiles c then
      "  if [[ -z \"$cur\" || \"$cur\" != -* ]]; then\n" ++
      "    COMPREPLY+=( $(compgen -f -- \"$cur\") )\n  fi\n"
    else ""
  fn ++ "() {\n" ++
  "  local cur=\"${COMP_WORDS[COMP_CWORD]}\"\n" ++
  "  COMPREPLY=( $(compgen -W \"" ++ words ++ "\" -- \"$cur\") )\n" ++
  fileLine ++
  "}\n" ++
  "complete -F " ++ fn ++ " " ++ c.name ++ "\n"

/-! ### zsh -/

/-- A zsh completion script using `_arguments`, with per-flag descriptions. -/
def zsh (c : Command α) : String :=
  let specs := match c.body with
    | .opts _ =>
      let m := c.toMeta
      m.flags.filter (fun f => isSafeName f.long) |>.map fun f =>
        let desc := f.help.replace "'" ""
        let arg := match f.typeName with
          | none => ""
          | some t => ":" ++ t ++ ":"
        match f.short with
        | some ch => "    '(-" ++ ch.toString ++ " --" ++ f.long ++ ")'{-" ++ ch.toString ++
            ",--" ++ f.long ++ "}'[" ++ desc ++ "]" ++ arg ++ "'"
        | none => "    '--" ++ f.long ++ "[" ++ desc ++ "]" ++ arg ++ "'"
    | .subs children =>
      children.filter (fun child => isSafeName child.name) |>.map fun child =>
        "    '" ++ child.name ++ "[" ++ child.description.replace "'" "" ++ "]'"
  let files := if wantsFiles c then ["    '*:file:_files'"] else []
  "#compdef " ++ c.name ++ "\n" ++
  "_" ++ safeName c ++ "() {\n" ++
  "  _arguments \\\n" ++
  " \\\n".intercalate (specs ++ files) ++ "\n" ++
  "}\n" ++
  "_" ++ safeName c ++ " \"$@\"\n"

/-! ### fish -/

/-- fish completions, one `complete` line per flag. -/
def fish (c : Command α) : String :=
  let lines := match c.body with
    | .opts _ =>
      let m := c.toMeta
      m.flags.filter (fun f => isSafeName f.long) |>.map fun f =>
        let desc := f.help.replace "'" ""
        let short := match f.short with
          | some ch => " -s " ++ ch.toString
          | none => ""
        let takesArg := if f.typeName.isSome then " -r" else ""
        "complete -c " ++ c.name ++ " -l " ++ f.long ++ short ++ takesArg ++
          " -d '" ++ desc ++ "'"
    | .subs _ =>
      let names := " ".intercalate (subcommandNames c)
      if names.isEmpty then [] else ["complete -c " ++ c.name ++ " -f -a '" ++ names ++ "'"]
  let files := if wantsFiles c then [] else ["complete -c " ++ c.name ++ " -f"]
  "\n".intercalate (lines ++ files) ++ "\n"

end Argus.Completions
