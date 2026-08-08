/-
Copyright (c) 2026 Jonathan Prieto-Cubides. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jonathan Prieto-Cubides
-/

import Argus

/-!
# Argus test runner

Assertion-based, no framework. Each check returns `none` on success or `some message`
on failure; `main` prints failures and exits non-zero.
-/

open Argus

argus_opts MacroOpts where
  verbose : Bool := Spec.switch "verbose" (some 'v') "Chatty output";
  jobs : Nat := Spec.flag "jobs" none "Worker count" Param.nat;
  files : List String := Spec.many (Spec.arg "FILE" "Input" Param.path)

private def check (name : String) (ok : Bool) : Option String :=
  if ok then none else some name

private def hasSubstr (hay needle : String) : Bool :=
  (hay.splitOn needle).length > 1

private def maxLineLength (text : String) : Nat :=
  text.splitOn "\n" |>.foldl (fun longest line => max longest line.length) 0

private def hasStyledSegment (text : TermColor.Text) (value : String)
    (style : TermColor.Style) : Bool :=
  text.segments.any fun segment => segment.text == value && segment.style == style

private def macroOptsChecks : List (Option String) :=
  let parse (argv : List String) : Option (Bool × Nat × List String) :=
    match Argus.run MacroOpts.spec argv with
    | .ok o => some (o.verbose, o.jobs, o.files)
    | .error _ => none
  [ check "argus_opts parses attached values and many positionals"
      (parse ["--verbose", "--jobs=4", "a.txt", "b.txt"] ==
        some (true, 4, ["a.txt", "b.txt"]))
  , check "argus_opts parses separate values and switch defaults"
      (parse ["--jobs", "2"] == some (false, 2, []))
  , check "argus_opts preserves declaration order in the result"
      (parse ["--jobs=3", "input"] == some (false, 3, ["input"]))
  , check "argus_opts metadata follows declaration order"
      (MacroOpts.spec.flagNames == ["verbose", "jobs"])
  ]

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

private def newParamChecks : List (Option String) :=
  [ check "int accepts a leading minus"
      (Param.int.decode "-42" matches .ok (-42 : Int))
  , check "int rejects trailing junk"
      (Param.int.decode "+42x" matches .error _)
  , check "bool is case-insensitive"
      (Param.bool.decode "TrUe" matches .ok true)
  , check "bool rejects unknown words"
      (Param.bool.decode "maybe" matches .error _)
  , check "duration converts every unit to seconds"
      (Param.duration.decode "1d2h3m4s" matches .ok 93784)
  , check "duration accepts bare seconds"
      (Param.duration.decode "90" matches .ok 90)
  , check "duration rejects an unknown unit"
      (Param.duration.decode "2x" matches .error _)
  , check "bytes converts decimal fractions"
      (Param.bytes.decode "1.5M" matches .ok 1500000)
  , check "bytes converts binary units and ignores B"
      (Param.bytes.decode "2GiB" matches .ok 2147483648)
  , check "bytes rejects an unknown suffix"
      (Param.bytes.decode "10MBx" matches .error _)
  , check "range accepts ordered bounds"
      (Param.range.decode "10..20" matches .ok (10, 20))
  , check "range rejects reversed bounds"
      (Param.range.decode "20..10" matches .error _)
  , check "csv decodes comma-separated values"
      ((Param.csv Param.nat).decode "1,2,3" matches .ok [1, 2, 3])
  , check "csv rejects an empty element"
      ((Param.csv Param.nat).decode "1,,3" matches .error _)
  , check "enum returns the selected value"
      ((Param.enum [("fast", 1), ("safe", 2)]).decode "safe" matches .ok 2)
  , check "enum is exact and case-sensitive"
      ((Param.enum [("fast", 1), ("safe", 2)]).decode "SAFE" matches .error _)
  , check "enum errors list accepted names"
      (match (Param.enum [("fast", 1), ("safe", 2)]).decode "slow" with
       | .error e => hasSubstr e.message "fast" && hasSubstr e.message "safe"
       | .ok _ => false)
  ]

/-- Error positions are columns within the value, not offsets into a joined argv. -/
private def errorPositionCheck : Option String :=
  match Param.nat.decode "12x" with
  | .error e => check "error column points inside the value" (e.pos == 2)
  | .ok _ => some "expected a failure on 12x"

/-! ### Spec backtracking -/

private def constThenArgSpec :=
  Spec.map2 (fun (n : Nat) (s : String) => (n, s))
    (Spec.const 7)
    (Spec.arg "TEXT" "Text" Param.str)

private def optNatThenTextSpec :=
  Spec.map2 (fun (n : Option Nat) (s : String) => (n, s))
    (Spec.opt (Spec.arg "NUMBER" "Number" Param.nat))
    (Spec.arg "TEXT" "Text" Param.str)

private def optFlagSpec :=
  Spec.opt (Spec.flag "mode" none "Mode" Param.str)

private def optDurationFlagSpec :=
  Spec.opt (Spec.flag "timeout" none "Timeout" Param.duration)

private def altLeftSpec :=
  Spec.alt (Spec.const "left") (Spec.const "right")

private def altFallbackSpec :=
  Spec.alt
    (Spec.map (fun (_ : Nat) => "left") (Spec.arg "NUMBER" "Number" Param.nat))
    (Spec.arg "TEXT" "Text" Param.str)

private def altThenArgSpec :=
  Spec.map2 (fun (s : String) (t : String) => (s, t))
    (Spec.alt
      (Spec.map (fun (_ : Nat) => "number") (Spec.arg "NUMBER" "Number" Param.nat))
      (Spec.const "fallback"))
    (Spec.arg "TEXT" "Text" Param.str)

private def specChecks : List (Option String) :=
  [ check "const returns its value"
      (Argus.run (Spec.const 7) [] matches .ok 7)
  , check "const consumes nothing before a positional"
      (Argus.run constThenArgSpec ["text"] matches .ok (7, "text"))
  , check "opt yields none on failure without an error"
      (Argus.run (Spec.opt (Spec.arg "NUMBER" "Number" Param.nat)) [] matches .ok none)
  , check "opt restores a failed positional for a later arg"
      (Argus.run optNatThenTextSpec ["text"] matches .ok (none, "text"))
  , check "opt yields some and consumes on success"
      (Argus.run optNatThenTextSpec ["7", "text"] matches .ok (some 7, "text"))
  , check "opt over a flag yields none when absent"
      (Argus.run optFlagSpec [] matches .ok none)
  , check "opt over a flag yields some when present"
      (Argus.run optFlagSpec ["--mode=fast"] matches .ok (some "fast"))
  , check "opt preserves invalid valued flags"
      (match Argus.run optDurationFlagSpec ["--timeout=wat"] with
       | .error [error] => error.message.startsWith "invalid value"
       | _ => false)
  , check "alt takes the left branch on success"
      (Argus.run altLeftSpec [] matches .ok "left")
  , check "alt falls back to the right branch, restoring what the left consumed"
      (Argus.run altFallbackSpec ["text"] matches .ok "text")
  , check "alt restores a failed positional for a later arg"
      (Argus.run altThenArgSpec ["text"] matches .ok ("fallback", "text"))
  ]

/-- Unclaimed input is a user error, not something to drop quietly. -/
private def leftoverChecks : List (Option String) :=
  let one := Spec.arg "X" "x" Param.str
  let msgs (argv : List String) : List String :=
    match Argus.run one argv with
    | .ok _ => []
    | .error es => es.map Err.message
  [ check "exactly the expected positionals succeeds"
      (Argus.run one ["a"] matches .ok "a")
  , check "one extra positional is reported"
      (msgs ["a", "b"] == ["unexpected argument 'b'"])
  , check "every extra positional is reported, not just the first"
      (msgs ["a", "b", "c"]
        == ["unexpected argument 'b'", "unexpected argument 'c'"])
  , check "extra positionals and unknown flags are reported together"
      ((msgs ["a", "b", "--zzz"]).length == 2)
  , check "many consumes the rest, so nothing is left over"
      (Argus.run (Spec.many (Spec.arg "F" "f" Param.str)) ["a", "b", "c"]
        matches .ok ["a", "b", "c"])
  ]

/-! ### Resolving a subcommand path for --help -/

private def resolveChecks : List (Option String) :=
  -- All children of a group share one result type; the application supplies the sum.
  let leaf := Argus.cmd "leaf"
    (Spec.map (fun (s : String) => s) (Spec.arg "S" "s" Param.str)) (description := "L")
  let inner := Argus.group "inner" [leaf] (description := "I")
  let build := Argus.cmd "build"
    (Spec.map (fun (_ : Bool) => "b") (Spec.switch "release" (some 'r') "R"))
    (description := "B")
  let root := Argus.group "tool" [build, inner] (version := some "1.0")
  [ check "an empty path resolves to the root"
      ((root.resolve []).name == "tool")
  , check "one level resolves to the child"
      ((root.resolve ["build"]).name == "build")
  , check "two levels resolve to the grandchild"
      ((root.resolve ["inner", "leaf"]).name == "leaf")
  , check "flags are stepped over while resolving"
      ((root.resolve ["--verbose", "build", "--help"]).name == "build")
  , check "valued global flags are stepped over while resolving"
      ((root.resolve ["--completions", "bash", "build"]).name == "build")
  , check "an unknown name stops at the last good command"
      ((root.resolve ["nope", "leaf"]).name == "tool")
  , check "resolving past a leaf stops at the leaf"
      ((root.resolve ["build", "extra"]).name == "build")
  , check "the resolved child carries its own flags, not the parent's"
      ((root.resolve ["build"]).flagNames == ["release"])
  , check "resolution keeps the full command path"
      ((root.resolvePath ["inner", "leaf"]).1 == ["tool", "inner", "leaf"])
  ]

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

-- Keep the user-facing diagnostic wording stable; the executable checks below also cover the
-- broader behavior, while these assertions make accidental message drift visible at compile time.
/-- info: "invalid value '12x' for '--jobs' at column 2; expected a natural number" -/
#guard_msgs in
#eval firstErr ["--jobs=12x", "needle"]

/-- info: "unknown flag '--jbs=2'; did you mean '--jobs'?" -/
#guard_msgs in
#eval firstErr ["--jbs=2", "needle", "--jobs=1"]

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

private def diagnosticChecks : List (Option String) :=
  let rendered := match Argus.run optsSpec ["--jobs=12x", "needle"] with
    | .ok _ => ""
    | .error errs => (Help.renderErrors errs).plainText
  [ check "value errors render a source location" (hasSubstr rendered "value for --jobs")
  , check "value errors preserve the given value" (hasSubstr rendered "12x")
  , check "value errors render a marker" (hasSubstr rendered "^")
  ]

/-! ### Subcommands -/

inductive SubcommandResult where
  | build (force : Bool)
  | echo (value : String)
  | status (verbose : Bool)
  deriving BEq

private def buildCommand : Command SubcommandResult :=
  Argus.cmd "build"
    (Spec.map SubcommandResult.build
      (Spec.switch "force" (some 'f') "Build even when unchanged"))
    (description := "Build the project")

private def statusCommand : Command SubcommandResult :=
  Argus.cmd "status"
    (Spec.map SubcommandResult.status
      (Spec.switch "verbose" (some 'v') "Show detailed status"))
    (description := "Show project status")

private def adminCommand : Command SubcommandResult :=
  Argus.group "admin" [statusCommand] (description := "Administrative commands")

private def echoCommand : Command SubcommandResult :=
  Argus.cmd "echo"
    (Spec.map SubcommandResult.echo (Spec.arg "VALUE" "Value to echo" Param.str))
    (description := "Echo a value")

private def subcommandApp : Command SubcommandResult :=
  Argus.group "tool" [buildCommand, adminCommand, echoCommand]

private def globalOptionApp : Command SubcommandResult :=
  Argus.groupWithOptions "tool"
    (Spec.map (fun (_ : Bool) => ())
      (Spec.switch "verbose" (some 'v') "Show detailed output"))
    [buildCommand, adminCommand, echoCommand]

private def subcommandChecks : List (Option String) :=
  let help := (Help.render subcommandApp 80).plainText
  let globalHelp := (Help.render subcommandApp 80 (includeGlobals := true)).plainText
  let optionHelp := (Help.render globalOptionApp 80 (includeGlobals := true)).plainText
  let longDescriptionCommand := Argus.cmd "long" (Spec.const ())
    (description := "A deliberately long command description that should wrap cleanly")
  let longDescriptionHelp := (Help.render longDescriptionCommand 24).plainText
  let leafHelp := (Help.render buildCommand 80).plainText
  let bash := Completions.bash subcommandApp
  let zsh := Completions.zsh subcommandApp
  let fish := Completions.fish subcommandApp
  let optionBash := Completions.bash globalOptionApp
  let optionZsh := Completions.zsh globalOptionApp
  let optionFish := Completions.fish globalOptionApp
  let leafBash := Completions.bash buildCommand
  let leafZsh := Completions.zsh buildCommand
  let leafFish := Completions.fish buildCommand
  [ check "two-level group dispatches and parses child flags"
      (subcommandApp.run ["build", "--force"] matches .ok (.build true))
  , check "nested group dispatches correctly"
      (subcommandApp.run ["admin", "status", "--verbose"] matches .ok (.status true))
  , check "missing subcommand lists available names"
      (match subcommandApp.run [] with
       | .error [e] =>
         hasSubstr e.message "build" && hasSubstr e.message "admin" && hasSubstr e.message "echo"
       | _ => false)
  , check "unknown subcommand suggests the closest name"
      (match subcommandApp.run ["buid"] with
       | .error [e] => hasSubstr e.message "buid" && hasSubstr e.message "build"
       | _ => false)
  , check "child flags are not parsed by the parent"
      (match subcommandApp.run ["--force"] with
       | .error [.missingSubcommand _ _] => true
       | _ => false)
  , check "child receives argv after its name"
      (subcommandApp.run ["echo", "payload"] matches .ok (.echo "payload"))
  , check "branch help lists subcommands"
      (hasSubstr help "COMMANDS:" && hasSubstr help "build [OPTIONS]"
        && hasSubstr help "echo <VALUE>"
        && hasSubstr help "Administrative commands")
  , check "branch help keeps terminal globals separate"
      (hasSubstr globalHelp "\nBASIC OPTIONS:\n  -h, --help"
        && hasSubstr globalHelp "\nCOMMANDS:\n")
  , check "group options render separately from terminal globals"
      (hasSubstr optionHelp "\nBASIC OPTIONS:\n  -h, --help"
        && hasSubstr optionHelp "\nOPTIONS:\n  -v, --verbose  Show detailed output"
        && hasSubstr optionHelp "\nCOMMANDS:\n")
  , check "group options parse before the child"
      (globalOptionApp.run ["--verbose", "build", "--force"] matches .ok (.build true))
  , check "group completions offer group options"
      (hasSubstr optionBash "--verbose" && hasSubstr optionZsh "--verbose"
        && hasSubstr optionFish "verbose")
  , check "header descriptions wrap to the render width"
      (maxLineLength longDescriptionHelp ≤ 24)
  , check "leaf help still lists options"
      (hasSubstr leafHelp "OPTIONS:" && hasSubstr leafHelp "--force"
        && !hasSubstr leafHelp "COMMANDS:")
  , check "branch bash completions offer child names"
      (hasSubstr bash "build" && hasSubstr bash "admin" && hasSubstr bash "echo")
  , check "branch zsh completions offer child names"
      (hasSubstr zsh "build" && hasSubstr zsh "admin" && hasSubstr zsh "echo")
  , check "branch fish completions offer child names"
      (hasSubstr fish "build" && hasSubstr fish "admin" && hasSubstr fish "echo")
  , check "leaf completions still offer flags"
      (hasSubstr leafBash "--force" && hasSubstr leafZsh "--force" && hasSubstr leafFish "force")
  ]

private def completionLeafCommand : Command SubcommandResult :=
  Argus.cmd "leaf"
    (Spec.map (fun (_ : Bool) => SubcommandResult.status true)
      (Spec.switch "verbose" (some 'v') "Leaf verbosity"))

private def unsafeCompletionCommand : Command SubcommandResult :=
  Argus.cmd "bad;name"
    (Spec.map (fun (_ : Bool) => SubcommandResult.echo "unsafe")
      (Spec.switch "unsafe" none "Unsafe command"))

private def contextCompletionApp : Command SubcommandResult :=
  Argus.group "tool"
    [buildCommand, Argus.group "inner" [completionLeafCommand], unsafeCompletionCommand]

private def completionArm (script path : String) : String :=
  match script.splitOn ("    \"" ++ path ++ "\")") with
  | _ :: rest =>
    match rest with
    | body :: _ =>
      match body.splitOn "    \"" with
      | body :: _ => body
      | [] => ""
    | [] => ""
  | [] => ""

private def completionContextChecks : List (Option String) :=
  let bash := Completions.bash contextCompletionApp
  let zsh := Completions.zsh contextCompletionApp
  let fish := Completions.fish contextCompletionApp
  let rootArm := completionArm bash ""
  let buildArm := completionArm bash "build"
  let innerArm := completionArm bash "inner"
  let leafArm := completionArm bash "inner leaf"
  let plainLeaf := Argus.cmd "plain"
    (Spec.map (fun (_ : Bool) => SubcommandResult.status false)
      (Spec.switch "plain-flag" none "Plain flag"))
  [ check "context root arm offers top-level children"
      (hasSubstr rootArm "build inner" && !hasSubstr rootArm "bad;name")
  , check "context leaf arm offers its own flags"
      (hasSubstr leafArm "--verbose")
  , check "context nested arm offers nested children"
      (hasSubstr innerArm "leaf")
  , check "context leaf flags stay in their own arms"
      (!hasSubstr buildArm "--verbose" && !hasSubstr leafArm "--force")
  , check "context unsafe names reach no generated script"
      (!hasSubstr bash "bad;name" && !hasSubstr zsh "bad;name" && !hasSubstr fish "bad;name")
  , check "context validation reports unsafe names"
      (Completions.validate contextCompletionApp == ["bad;name"])
  , check "context zsh uses a subcommand state"
      (hasSubstr zsh "1:subcommand:->subcommand" && hasSubstr zsh "_describe")
  , check "context fish uses nested command conditions"
      (hasSubstr fish "complete -c tool"
        && !hasSubstr fish "complete -c build"
        && hasSubstr fish "__fish_seen_subcommand_from inner" && hasSubstr fish "leaf")
  , check "plain leaf completions still offer flags"
      (hasSubstr (Completions.bash plainLeaf) "--plain-flag"
        && hasSubstr (Completions.zsh plainLeaf) "--plain-flag"
        && hasSubstr (Completions.fish plainLeaf) "plain-flag")
  ]

private def completionSafetyChecks : List (Option String) :=
  let quoted := Argus.cmd "quoted"
    (Spec.map (fun (_ : Bool) => SubcommandResult.status true)
      (Spec.switch "quoted" none "it's ] \\ $ (metadata)"))
  let zsh := Completions.zsh quoted
  let fish := Completions.fish quoted
  [ check "completion safety rejects shell metacharacters"
      (!Completions.isSafeName "$" && !Completions.isSafeName "`"
        && !Completions.isSafeName "'" && !Completions.isSafeName ";"
        && !Completions.isSafeName " ")
  , check "completion metadata escapes shell syntax"
      (hasSubstr zsh "\\]" && hasSubstr zsh "'\\''"
        && hasSubstr fish "\\'")
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
  let scheme := TermColor.ColorScheme.monokai
  let themedFlagStyle := TermColor.Style.combine TermColor.Style.bold
    (TermColor.Style.fg scheme.green)
  let themedArgStyle := TermColor.Style.combine TermColor.Style.bold
    (TermColor.Style.fg scheme.yellow)
  let themedTypeStyle := TermColor.Style.fg scheme.orange
  let themedTitleStyle := TermColor.Style.combine
    (TermColor.Style.combine TermColor.Style.bold TermColor.Style.underline)
    (TermColor.Style.fg scheme.pink)
  let lines := (Help.render longCmd 40).plainText.splitOn "\n"
  let flagLines := lines.filter (fun l => (l.splitOn "--verbose").length > 1)
  let contLines := lines.filter (fun l => (l.splitOn "detail").length > 1)
  let themed := Help.render longCmd 40 scheme
  let typed := Argus.cmd "typed"
    (Spec.flag "jobs" none "Worker count" Param.nat)
  let typedThemed := Help.render typed 40 scheme
  let globals := (Help.render longCmd 40 (includeGlobals := true)).plainText
  let commandThemed := Help.render subcommandApp 80 scheme
  let titleThemed := Help.render longCmd 40 scheme
  let nested := (Help.render echoCommand 80 (commandPath := ["tool", "echo"])).plainText
  [ check "no line has trailing whitespace"
      (lines.all fun l => !l.endsWith " ")
  , check "the long description wraps onto more than one line"
      (flagLines.length == 1 && contLines.length == 1 && flagLines != contLines)
  , check "continuation lines are indented, not flush left"
      (contLines.all fun l => l.startsWith "  ")
  , check "no rendered line exceeds the requested width"
      (lines.all fun l => l.length <= 40)
  , check "help uses the supplied color scheme"
      (hasStyledSegment themed "--verbose" themedFlagStyle
        && hasStyledSegment typedThemed " NAT" themedTypeStyle)
  , check "help titles are highlighted separately from commands"
      (hasStyledSegment titleThemed "demo" themedTitleStyle)
  , check "command synopses keep option and argument colors"
      (hasStyledSegment commandThemed " [OPTIONS]" themedFlagStyle
        && hasStyledSegment commandThemed " <VALUE>" themedArgStyle)
  , check "nested help keeps the full command path"
      (hasSubstr nested "tool echo\n"
        && hasSubstr nested "\nUSAGE:\n  tool echo <VALUE>")
  , check "help separates terminal globals from command flags"
      (hasSubstr globals "\nBASIC OPTIONS:\n  -h, --help"
        && hasSubstr globals "--completions SHELL"
        && hasSubstr globals "\nOPTIONS:\n  -v, --verbose"
        && !hasSubstr globals "\nOPTIONS:\n  -h, --help")
  , check "help uses Lake-style headings and placeholders"
      (hasSubstr globals "\nUSAGE:\n  demo [OPTIONS]"
        && !hasSubstr globals "[FLAGS]")
  ]

def main : IO UInt32 := do
  let results :=
    macroOptsChecks ++ paramChecks ++ newParamChecks ++ [errorPositionCheck] ++ specChecks
      ++ leftoverChecks
      ++ editDistanceChecks ++ metaChecks ++ runnerChecks ++ messageChecks
      ++ diagnosticChecks
      ++ subcommandChecks ++ resolveChecks
      ++ completionContextChecks
      ++ completionSafetyChecks
      ++ helpChecks
  let failures := results.filterMap id
  if failures.isEmpty then
    IO.println s!"all {results.length} checks passed"
    return 0
  else
    for f in failures do
      IO.eprintln s!"FAIL: {f}"
    IO.eprintln s!"{failures.length} of {results.length} checks failed"
    return 1
