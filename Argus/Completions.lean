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

## Context

Each generated script follows safe, non-flag words on the command line to the matching
node. Branches offer child names; leaves offer their own flags and path arguments.

## Injection

Flag names are interpolated into shell word lists. A name containing `$`, a backtick, or
a quote would execute when the script is sourced. `isSafeName` is the gate, and every
generator filters through it, so a malformed spec produces a smaller script rather than
a dangerous one. `validate` reports what was dropped.
-/

namespace Argus.Completions

variable {α : Type}

/-- Shell-word-safe: ASCII letters, digits, `-`, `_`. -/
def isSafeName (s : String) : Bool :=
  !s.isEmpty && s.all fun c =>
    c.isAlphanum || c == '-' || c == '_'

private def invalidNames (c : Command α) : List String :=
  match c with
  | ⟨_, _, _, .opts spec⟩ =>
    (spec.toMeta.flags.map (·.long)).filter (fun n => !isSafeName n)
  | ⟨_, _, _, .subs children⟩ =>
    let childNames := children.map (·.name) |>.filter (fun n => !isSafeName n)
    childNames ++ children.flatMap fun child => invalidNames child
termination_by sizeOf c
decreasing_by
  have h := List.sizeOf_lt_of_mem ‹child ∈ children›
  simp at *
  omega

/-- Names that would be unsafe to interpolate into a script. Empty means the command is
safe to generate from. -/
def validate (c : Command α) : List String :=
  invalidNames c

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
  String.ofList (c.name.toList.map fun ch => if isSafeName ch.toString then ch else '_')

private def commandTarget (c : Command α) : String :=
  if isSafeName c.name then c.name else "_" ++ safeName c

private def shellQuote (value : String) : String :=
  "'" ++ value.replace "'" "'\\''" ++ "'"

private def zshEscape (value : String) : String :=
  (value.replace "\\" "\\\\").replace "]" "\\]"

private def fishQuote (value : String) : String :=
  "'" ++ (value.replace "\\" "\\\\").replace "'" "\\'" ++ "'"

private def nodes (path : List String) (c : Command α) :
    List (List String × Command α) :=
  match c with
  | ⟨name, version, description, .opts spec⟩ =>
    [(path, { name, version, description, body := .opts spec })]
  | ⟨name, version, description, .subs children⟩ =>
    let c := { name, version, description, body := .subs children }
    let here := [(path, c)]
    here ++ children.flatMap fun child =>
      if isSafeName child.name then nodes (path ++ [child.name]) child else []
termination_by sizeOf c
decreasing_by
  have h := List.sizeOf_lt_of_mem ‹child ∈ children›
  simp at *
  omega

private def pathKey (path : List String) : String :=
  " ".intercalate path

/-! ### bash -/

private def bashWords (c : Command α) : String :=
  match c.body with
  | .opts _ => " ".intercalate (flagWords c)
  | .subs _ => " ".intercalate (subcommandNames c)

private def bashFiles (c : Command α) : String :=
  if wantsFiles c then
    "      if [[ -z \"$cur\" || \"$cur\" != -* ]]; then\n" ++
    "        COMPREPLY+=( $(compgen -f -- \"$cur\") )\n" ++
    "      fi\n"
  else ""

private def bashArm (node : List String × Command α) : String :=
  let path := pathKey node.1
  let c := node.2
  "    \"" ++ path ++ "\")\n" ++
  "      COMPREPLY=( $(compgen -W \"" ++ bashWords c ++
    "\" -- \"$cur\") )\n" ++
  bashFiles c ++
  "      ;;\n"

/-- A bash completion script. Source it, or drop it in /etc/bash_completion.d. -/
def bash (c : Command α) : String :=
  let fn := "_" ++ safeName c ++ "_completions"
  fn ++ "() {\n" ++
  "  local cur=\"${COMP_WORDS[COMP_CWORD]}\"\n" ++
  "  local path=\"\" word i\n" ++
  "  for ((i=1; i<COMP_CWORD; i++)); do\n" ++
  "    word=\"${COMP_WORDS[i]}\"\n" ++
  "    if [[ \"$word\" != -* ]]; then\n" ++
  "      [[ -n \"$path\" ]] && path+=\" \"\n" ++
  "      path+=\"$word\"\n" ++
  "    fi\n" ++
  "  done\n" ++
  "  case \"$path\" in\n" ++
  "".intercalate ((nodes [] c).map bashArm) ++
  "    *) COMPREPLY=() ;;\n" ++
  "  esac\n" ++
  "}\n" ++
  "complete -F " ++ fn ++ " -- " ++ commandTarget c ++ "\n"

/-! ### zsh -/

private def zshFlagSpec (f : FlagInfo) : String :=
  let desc := zshEscape f.help
  let arg := match f.typeName with
    | none => ""
    | some t => ":" ++ zshEscape t ++ ":"
  let short := f.short.bind fun ch =>
    if isSafeName ch.toString then some ch else none
  let spec := match short with
    | some ch =>
      let s := ch.toString
      "(-" ++ s ++ " --" ++ f.long ++ "){-" ++ s ++ ",--" ++ f.long ++
        "}[" ++ desc ++ "]" ++ arg
    | none => "--" ++ f.long ++ "[" ++ desc ++ "]" ++ arg
  shellQuote spec

private def zshFlagSpecs (c : Command α) : List String :=
  c.toMeta.flags.filter (fun f => isSafeName f.long) |>.map zshFlagSpec

private def zshLeafArm (path : List String) (c : Command α) : String :=
  let specs := zshFlagSpecs c ++ (if wantsFiles c then ["'*:file:_files'"] else [])
  let body := if specs.isEmpty then
      "          :\n"
    else
      "          _arguments \\\n" ++
        " \\\n".intercalate (specs.map fun spec => "            " ++ spec) ++ "\n"
  "        \"" ++ pathKey path ++ "\")\n" ++ body ++ "          ;;\n"

private def zshBranchArm (path : List String) (c : Command α) : String :=
  let choices := match c.body with
    | .opts _ => []
    | .subs children =>
      children.filter (fun child => isSafeName child.name) |>.map fun child =>
        shellQuote (child.name ++ ":" ++ zshEscape child.description)
  "        \"" ++ pathKey path ++ "\")\n" ++
  "          choices=(" ++ " ".intercalate choices ++ ")\n" ++
  "          _describe 'subcommand' choices\n" ++
  "          ;;\n"

private def zshArm (node : List String × Command α) : String :=
  match node.2.body with
  | .opts _ => zshLeafArm node.1 node.2
  | .subs _ => zshBranchArm node.1 node.2

/-- A zsh completion script using _arguments state dispatch and _describe. -/
def zsh (c : Command α) : String :=
  let fn := "_" ++ safeName c
  "#compdef " ++ commandTarget c ++ "\n" ++
  fn ++ "() {\n" ++
  "  local state path=\"\" i word\n" ++
  "  local -a choices\n" ++
  "  for ((i=2; i<CURRENT; i++)); do\n" ++
  "    word=\"${words[i]}\"\n" ++
  "    if [[ \"$word\" != -* ]]; then\n" ++
  "      [[ -n \"$path\" ]] && path+=\" \"\n" ++
  "      path+=\"$word\"\n" ++
  "    fi\n" ++
  "  done\n" ++
  "  _arguments -C \\\n" ++
  "    '1:subcommand:->subcommand' \\\n" ++
  "    '*::argument:->argument'\n" ++
  "  case \"$state\" in\n" ++
  "    subcommand|argument)\n" ++
  "      case \"$path\" in\n" ++
  "".intercalate ((nodes [] c).map zshArm) ++
  "      esac\n" ++
  "      ;;\n" ++
  "  esac\n" ++
  "}\n" ++
  fn ++ " \"$@\"\n"

/-! ### fish -/

private def descendantNames (c : Command α) : List String :=
  match c with
  | ⟨_, _, _, .opts _⟩ => []
  | ⟨_, _, _, .subs children⟩ =>
    children.flatMap fun child =>
      if isSafeName child.name then [child.name] ++ descendantNames child else []
termination_by sizeOf c
decreasing_by
  have h := List.sizeOf_lt_of_mem ‹child ∈ children›
  simp at *
  omega

private def fishCondition (path : List String) (c : Command α) : Option String :=
  match path with
  | [] => match c.body with
    | .opts _ => none
    | .subs _ => some "__fish_use_subcommand"
  | _ =>
    let seen := "; and ".intercalate
      (path.map fun name => "__fish_seen_subcommand_from " ++ name)
    let blocked := (descendantNames c).map
      (fun name => "not __fish_seen_subcommand_from " ++ name)
    some (seen ++ if blocked.isEmpty then "" else "; and " ++ "; and ".intercalate blocked)

private def fishWhen (condition : Option String) : String :=
  match condition with
  | none => ""
  | some value => " -n " ++ fishQuote value

private def fishFlagLine (target : String) (when : String) (f : FlagInfo) : String :=
  let short := f.short.bind fun ch =>
    if isSafeName ch.toString then some (" -s " ++ ch.toString) else none
  let takesArg := if f.typeName.isSome then " -r" else ""
  "complete -c " ++ target ++ " -l " ++ f.long ++ (short.getD "") ++ takesArg ++ when ++
    " -d " ++ fishQuote f.help

private def fishNodeLines (target : String) (node : List String × Command α) : List String :=
  let path := node.1
  let c := node.2
  let when := fishWhen (fishCondition path c)
  match c.body with
  | .opts _ =>
    let flags := c.toMeta.flags.filter (fun f => isSafeName f.long) |>.map
      (fishFlagLine target when)
    let noFiles := if wantsFiles c then [] else ["complete -c " ++ target ++ " -f" ++ when]
    flags ++ noFiles
  | .subs _ =>
    let names := " ".intercalate (subcommandNames c)
    if names.isEmpty then []
    else ["complete -c " ++ target ++ " -f" ++ when ++ " -a " ++ fishQuote names]

/-- fish completions use command-line conditions for every safe node in the tree. -/
def fish (c : Command α) : String :=
  let target := commandTarget c
  "\n".intercalate ((nodes [] c).flatMap (fishNodeLines target)) ++ "\n"

end Argus.Completions
