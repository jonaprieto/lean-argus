/-
Copyright (c) 2026 Jonathan Cubides. All rights reserved.
-/

import Argus.Runner
import TermColor.Diagnostics

/-!
# Argus.Diagnostics: structured usage-error rendering

Argus keeps parsing errors small and typed. This adapter gives those errors source labels at the
last responsible moment, so `Argus.Runner` stays independent of terminal presentation.
-/

namespace Argus

open TermColor.Diagnostics

structure DiagnosticReport where
  sources : Sources
  diagnostics : List Diagnostic

private def sourceFor (err : Err) : Source :=
  match err with
  | .badValue flag given _ => Source.named s!"value for --{flag}" given
  | _ => Source.named "" ""

private def expectedText (expected : List String) : String :=
  if expected.isEmpty then "unexpected input"
  else "expected " ++ ", ".intercalate expected

private def diagnosticFor (index : SourceId) (err : Err) : Diagnostic :=
  match err with
  | .badValue flag _ parseError =>
    (Diagnostic.error s!"invalid value for '--{flag}'").withLabel
      (Label.primary (Span.point index parseError.pos) (expectedText parseError.expected))
  | _ => Diagnostic.error err.message

private def indexed : Nat → List Err → List (SourceId × Err)
  | _, [] => []
  | index, err :: rest => (index, err) :: indexed (index + 1) rest

/-- Convert Argus errors to sources and structured diagnostics for a pure renderer. -/
def errorsToDiagnostics (errs : List Err) : DiagnosticReport :=
  { sources := errs.toArray.map sourceFor
    diagnostics := indexed 0 errs |>.map fun (index, err) => diagnosticFor index err }

end Argus
