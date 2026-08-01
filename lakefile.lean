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
  @ "7c627ca1785694d634baaf1ac3ea33a106902d87"

@[default_target]
lean_lib «Argus» where
  globs := #[.andSubmodules `Argus]

lean_exe «demo» where
  root := `Demo
  srcDir := "examples"

lean_exe «tests» where
  root := `Tests
  srcDir := "test"
