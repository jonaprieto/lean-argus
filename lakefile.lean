import Lake
open Lake DSL

package «argus» where
  version := v!"0.1.0"
  leanOptions := #[⟨`autoImplicit, false⟩, ⟨`relaxedAutoImplicit, false⟩]

-- Pinned by SHA: the grade algebra and parser semantics must not move underfoot.
require grip from git
  "https://github.com/jonaprieto/grip" @ "eb29a2331729a7087eab54838557e7490e802a29"

require «termcolor» from git
  "https://github.com/jonaprieto/lean-termcolor.git"
  @ "1d78a0ce44f3f97fe55f5b02d13fa42af55e8229"

require «termcolor-layout» from git
  "https://github.com/jonaprieto/lean-termcolor-layout.git"
  @ "b4cebaf65c8cb3a58b97acaeadf1b8aae275c19b"

-- Only `Argus.Term` needs this. Listed here because Lake has no per-library requires;
-- the layering is enforced by the module lists below, not by the dependency set.
require «termcolor-terminal» from git
  "https://github.com/jonaprieto/lean-termcolor-terminal.git"
  @ "67f30f2f16da5d95861668f44e547a7b4301b947"

/-- The pure library. Deps: grip, termcolor, termcolor-layout. Listed explicitly rather
than globbed so that adding a module cannot silently widen what a consumer links. -/
@[default_target]
lean_lib «Argus» where
  globs := #[.one `Argus, .one `Argus.Param, .one `Argus.Spec, .one `Argus.Runner,
             .one `Argus.Command, .one `Argus.Help, .one `Argus.Completions,
             .one `Argus.Macro]

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
