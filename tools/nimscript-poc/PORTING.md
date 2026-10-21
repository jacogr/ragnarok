# NimScript POC port plan

Scope: translate `tools/pvm_reference_summary.py` (cell escaping, evidence validation and
Markdown rendering) to `tools/pvm_reference_summary.nims`. Keep the Python oracle and
all production Make/CI callers. This is an opt-in tooling experiment, not a production
compiler change or a replacement for independent protocol oracles.

Module graph: stdlib JSON, strings, Unicode, sets and tables only; no external packages.
Port order: `cell`, identity predicates, `summarize_reference`, standalone CLI.
CLI: `nim e --hints:off tools/pvm_reference_summary.nims -- REPORT.json OUTPUT.md`.
The explicit `--` separates compiler arguments from script arguments.

Baseline: `PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tools:tests python3 -m unittest
 test_pvm_reference_summary -q`: five tests pass before translation (2026-10-21).

Parity gate: run the retained Python oracle against itself, then against NimScript on the
same valid/invalid JSON reports. Compare successful Markdown bytes and failure acceptance;
CLI transport and compiler exception backtraces are outside the renderer API contract.
Test Unicode whitespace/truncation, escaping, duplicate/unknown stages, false integer codes,
missing stages, completed ordering, empty plans and backend-neutral roles. Run the same
corpus compiled with Nim 2 in debug/release to check that the pure renderer is reusable.

Traceability:

| Existing source test | POC coverage |
| --- | --- |
| test_complete_and_partial_tables | complete, failed, running, absent stages |
| test_selected_backend_and_neutral_probe | neutral and explicit backend |
| test_forged_success_rejected | missing/failed/duplicate/unknown/bool evidence |
| test_missing_report_replaces_green_artifact | Existing production CLI unchanged; out of POC scope |
| test_cli_table_matches_download | POC output compared byte-for-byte to Python renderer |

Domain: JSON reports produced by the reference runner, plus malformed-schema rejection
cases. No attempt to reproduce Python exception stack traces. Python arbitrary-size integers
beyond signed 64-bit JSON values are outside this POC; decide before production adoption.
No source bugs or intentional renderer behavior changes identified at planning time.


## Evaluation and observed results

Use `make check-nimscript-poc` for the complete opt-in comparison. Make provisions the existing
pinned toolchain; the runner resolves `nim` beside the real `nimpretty` binary in its verified
archive. No new download, compiler upgrade, PATH export, or production summary caller is needed.
Generated inputs, identical `.nim` copies for compiled controls, caches and logs live under
`build/nimscript-poc/`. Normal `make check` and CI groups do not execute this experiment.

The pinned Nimony 0.6.3 rejects `nimony e` with `invalid command, e`; its help lists compiled
backends and semantic checking, with no standalone NimScript evaluator. Nifler configuration
support mentioned in upstream design documentation does not establish a standalone Nimony
NimScript runner. See [Nimony design](https://github.com/nim-lang/nimony/blob/master/doc/design.md).

Nim 2.2.12 is already physically present in the full formatter archive on supported local/CI
hosts after toolchain setup. `tools/setup_nimony.py` deliberately exports only Nimony and the
formatter directory; the Python-only CI job does not provision that toolchain. Existing CI
availability therefore permits explicit reuse, but does not imply this POC is CI-tested.

Local macOS ARM64 evidence (2026-10-21): 34 reports pass in NimScript, Nim 2 compiled debug,
and compiled release. The five existing Python source tests passed before translation.
For valid reports, compare exact UTF-8 Markdown bytes. Invalid reports compare rejection and
absence of output; Python exceptions and compiler backtraces are intentionally not byte-compared.
No Linux CI run was requested or claimed.

Five fresh-process renders of the same complete report gave these median startup + import +
parse + render + write times (seconds): Python 0.0340; NimScript 0.4829; compiled debug 0.0041;
compiled release 0.0035. Compiled build time is excluded. These small local observations are
not a general performance claim. The full correctness runs include invalid-input diagnostics
and must not be used as a performance comparison.

NimScript offers familiar Nim syntax, static type checking, pure shared helpers and execution
without a C compilation step. Python already supplies cross-platform scripting and currently
has clearer subprocess/network/timeout/library support in this repository. NimScript uses
Nim's compiler VM and cannot call FFI-backed libraries; identity regexes were replaced with
ASCII predicates, and the CLI explicitly separates compiler/script arguments. The faithful
translation is roughly twice the source size because it spells out Python truth/Unicode rules.
See [NimScript documentation](https://nim-lang.org/docs/nims.html).

Recommendation: use the bundled Nim 2 executable for any selected `.nims` tooling experiments;
keep Nimony as the production target. Consider small deterministic file/JSON/build helpers,
but retain Python independent protocol references and process-heavy harnesses. This renderer
works as a POC, but its existing Python integration and faster startup favor keeping the current
production implementation until language consistency justifies the migration cost.

## Deliberate scope limits

This is renderer parity for the producer's JSON schema, not a drop-in replacement for
`summarize_tests.py`: append-to-Actions behavior, artifact replacement on report-read failures,
argument diagnostics and all other summary kinds remain in the existing production CLI.
Nested containers in free-form metadata/error fields are outside the producer schema and are
rejected by the POC rather than reproducing Python container repr. Integers beyond signed
64-bit range are also outside scope. These limits need decisions/tests before wider adoption.
The corpus does not establish support for subprocess streaming, timeouts, networking or FFI.
