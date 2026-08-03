import Lake
open Lake DSL

package «argus» where
  version := v!"0.2.3"
  leanOptions := #[⟨`autoImplicit, false⟩, ⟨`relaxedAutoImplicit, false⟩]

-- Pinned by SHA: the grade algebra and parser semantics must not move underfoot.
require grip from git
  "https://github.com/jonaprieto/grip" @ "eb29a2331729a7087eab54838557e7490e802a29"

require «termcolor» from git
  "https://github.com/jonaprieto/lean-termcolor.git"
  @ "ac9a102562fa65435365758cf5fe5ac95c6a7a92"

require «termcolor-layout» from git
  "https://github.com/jonaprieto/lean-termcolor-layout.git"
  @ "d45b699afecb7cca8328778b1f7cc6a793b43dcd"

require «termcolor-diagnostics» from git
  "https://github.com/jonaprieto/lean-termcolor-diagnostics.git"
  @ "315f84249c6c9874221ec20f419ad03f6c339815"

-- Only `Argus.Term` needs this. Listed here because Lake has no per-library requires;
-- the layering is enforced by the module lists below, not by the dependency set.
require «termcolor-terminal» from git
  "https://github.com/jonaprieto/lean-termcolor-terminal.git"
  @ "93ffbcd8c3f69dec0d4e38550aaa31245edbd48a"

/-- The pure library. Deps: grip, termcolor, termcolor-layout. Listed explicitly rather
than globbed so that adding a module cannot silently widen what a consumer links. -/
@[default_target]
lean_lib «Argus» where
  globs := #[.one `Argus, .one `Argus.Param, .one `Argus.Spec, .one `Argus.Runner,
             .one `Argus.Command, .one `Argus.Help, .one `Argus.Completions,
             .one `Argus.Macro, .one `Argus.Diagnostics]

/-- The IO layer, opt-in. Adds termcolor-terminal. A consumer that only parses, or that
renders to a fixed width, never imports this and never links it. -/
lean_lib «Argus.Term» where
  globs := #[.one `Argus.Term]

lean_lib «Argus.Properties» where
  globs := #[.one `Argus.Properties]

lean_exe «demo» where
  root := `Demo
  srcDir := "examples"

lean_exe «tests» where
  root := `Tests
  srcDir := "test"

lean_exe «readme» where
  root := `Readme
  srcDir := "test"

lean_exe «completion-fixture» where
  root := `CompletionFixture
  srcDir := "test"
