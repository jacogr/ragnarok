# Adding and changing verification

Feature PRs own their test sources, required execution metadata and feature specification.
Avoid adding rolling global totals or feature-by-feature progress notes to the shared testing index. Record
coverage details and reproduction commands in the feature's `spec/` document instead.

## Native suites and compiler rejections

Add native application assertions as `tests/unit/<source-family>/test_<suite>.nim` with an explicit
`.output` contract. Suite identities are discovered from these files in alphabetical order; do not
maintain a separate suite list. Helpers belong in `tests/support/` and
rejection fixtures in `tests/native/compile_fail/`. Duplicate identities, misplaced Nim files,
empty discovery and missing output contracts fail before setup.

Declare the suite's source directory, library order, observer flags and fixture requirements in
`tools/native_requirements/<source-family>/<suite>.json`. Linking profiles are derived from these
existing requirements; no central unit/link registration is needed. Keep independent profile fields
alphabetical and retain ordered link options. If the suite must produce ARC evidence, declare its
report key in the source header with `# @@Verification={"arc": "example_arc_release"}`. The existing
ARC helper and fresh-evidence checks remain required. Use a distinct report key such as
`<suite>_arc_release`; preflight rejects keys that overlap runtime failure families.

Static fixture dependencies belong in the same per-suite requirements file, for example
`"fixtures": ["state_report"]`; omit the field when no static input is needed. Keep this list
alphabetical and unique. Each ID is discovered from a `*.fixture.json` descriptor beside its
input data under `tests/fixtures/`. A descriptor owns its environment variable, target and exact
member SHA-256 pins; adding a fixture or consumer requires no runner registration. Generated
fixtures declare a `"provider"` ID in the same requirements file, with an optional semantic
`"variant"` (defaulting to `"default"`). Keep `"prepared": true` for these consumers; preflight
checks the flag and provider/variant together. Provider IDs come from decorated `unit_<id>_fixture`
callables in `tools/native_fixtures.py`; there is no consumer alias table. Providers return variant
contracts, which the wrapper binds to suites from their requirements. The decorator declares
execution group/rank, required resources and any historical evidence key/filename. Add a provider
at its definition and its consumers in their own requirements; no runner dispatch or pipeline-list
edit is needed. See [infrastructure](infrastructure.md) for lifecycle and evidence details.

Compiler Guards are selective protection against documented compiler regressions, distinct
ownership/borrowing/lowering hazards, and material application admission or safety regressions.
A new feature does **not** automatically need private-field, accessor, nominal-pair or
invalid-constant fixtures. Do not add exhaustive language-rule matrices or move those matrices
into another suite or scheduled job. Normal runtime misuse belongs in the separate Contract
suite; ordinary feature behavior belongs in unit/integration tests.

Each proposed Guard must name its distinct mechanism or explain the concrete unsafe consumer
behavior it prevents. “The compiler might have bugs” and restating a language rule are insufficient.
For a compiler regression, link the original defect/reproduction; for an application boundary,
identify what unauthenticated, incomplete, dangling or multiply owned state would otherwise reach
the consumer. Prefer one focused witness per mechanism to copies for every owner or pipeline stage.
See the [reviewed retained set](../../spec/compiler-guards-review-2026-10-30.md).

Compiler rejection sources belong under `tests/native/compile_fail/`, with one source-local header:

```nim
# @@Verification={"group":"ownership_compile","expected":"'=dup' is not available for type <ScalarOwner>","build_name":"nimony-scalar-copy","rationale":"Scalar-only owners previously bypassed unavailable copy/dup hooks without a destructor.","reference":"spec/nimony-nightly-2026-10-21.md"}
```

Supported groups are `nominal` (a justified admission boundary), `schemas` (closed canonical
scalar admission), and `ownership_compile` (actual lowering). Every declaration requires a
nonempty `rationale` and `reference` to the defect/reproduction or affected consumer. Nominal
checks require an `early` pair containing the exact callee and positional mismatch. Ownership
checks require a unique `build_name`; `offload: true` retains the proof pool's enabled ABI/define.
Preserve exact rejection diagnostics: a different compiler error or a successful compile cannot
pass. Add predicate tests for any new diagnostic mechanism. Fixture discovery, not a central name
list or sidecar registration, owns scheduling; report completeness checks require the exact set
of expected identities, without missing, duplicate, substituted or failed rows.

## Runtime failures and independent corpora

Add ordinary runtime probes to `tools/failure_suites/<family>.json`, one case per line, with
automatic alphabetical scheduling from those validated files. No runner edit or second family list is needed.
The declared cases supply expected identities before execution; never infer expectations from
observed results. Specialized drivers own typed enum cases tagged with `# @@ProbeCases` and expose
`--list-cases`; add their origin/diagnostic combinations to the specialized source-owned plan.
Preserve positive controls and intentional language-policy cases. Establish the intended error/state
before forbidden extraction. A setup refusal must have a different status or diagnostic from the
expected access assertion; do not accept any crash as success. Avoid exposing a static postcondition
that turns the runtime witness into compile-time rejection.

Build sharing is opt-in via a family's `bundle` field. Use a small group with matching source
directory, libraries and defines, export `runFailureProbe(selection: string)` from each fixture,
and retain its standalone `when isMainModule` entry. Cases keep their original identities,
selection argument and precise diagnostics. Measure representative standalone/bundled cold-cache
builds and run positive controls before expanding a bundle. Do not trade probe coverage or process
isolation for fewer binaries. Selected production-profile regressions need a documented defect or
mechanism rationale; preserve their ordinary checked-profile execution.

Typed specialized drivers declare `# @@Verification={"group": "failure_driver"}` in the header
of `tests/native/nimony_<family>_results.nim`, alongside their `@@ProbeCases` enum. Source discovery
supplies family paths; removing the header from a typed probe fails preflight. Register a matching
`run_<family>` handler in `tools/failure_controls.py` with `@CONTROLS.case`, its execution rank
and source-based case planner. Declare native `libraries` and fixture `sources` for non-typed
controls; typed drivers supply their own source root. Each handler owns build flags, fixtures and exact predicates.
Discovery requires one handler per marked source. Language/resource controls use the same local
registration with explicit plans and identity fields. No central driver or handler list is needed.

Independent expected values remain in `tests/` oracles. Corpus orchestration belongs in the
appropriate `tools/corpus_*.py` module; preserve request hashes, build profiles, complete output
comparison and explicit scheduling. Register a named `<feature>_corpus` callable with the owning
module's `@CORPORA.case`; return its verdict instead of separately assigning a report key. The
registration supplies both scheduling and completeness expectations. Preserve shared-build
dependencies in the feature/task order. A case that reads a preceding corpus result must declare
that producer with `@CORPORA.case(requires=('producer_corpus',))`; dependencies may cross feature
groups but must precede the consumer. Randomized corpus sharding keeps each connected dependency
bundle together; shared helpers that read the report carry the same dependency requirement.
Independent cases need no shard assignment or timing declaration. New `corpus_*.py` modules are discovered automatically;
declare `CorpusGroup(order=<unique rank>)` locally, with `resources` for generated fixture inputs.
Leave gaps between dependency ranks to allow insertion without renumbering other features.

## E2E tasks and shared provenance

Declare E2E workloads and selftests as named `@PLAN.workload` and `@PLAN.selftest` callables in
`tools/e2e_checks.py`. Their names supply both scheduling and required report identities; return
verdicts instead of adding a parallel coverage list. Use ordered `@PLAN.setup` tasks for shared
peer builds. Keep resource limits, workload order and cleanup in the owning task. Direct offload
selftest callables are shared with the E2E plan through a context adapter.

Runtime, E2E and compiler-guard reports share `runtime_provenance.runtime_sources()` discovery.
New project modules, helpers and fixtures are included automatically; retain explicit pinned
upstream input contracts and generated-fixture hashes.

## Python reference and tooling tests

Test observable failures, not the current implementation's shape. State what concrete wrong result,
lost coverage, unsafe operation or misleading verdict each test prevents. Avoid assertions about
comments, formatting, headings, display names, job order, YAML anchor names, incidental grouping or
historical organization. Do not replace these with snapshots or a more elaborate configuration parser.
For CI partition changes, use the configured partitions and require discovered work exactly once;
retain fixed limits only when they express a deliberate safety or resource requirement.

Keep independent mathematical/protocol equations, literal boundary expectations, frozen-vector
provenance and semantic witnesses. A hash detects fixture drift; it does not establish protocol
correctness by itself. Do not calculate an expected answer by calling the function under test again
or copying its implementation. Repeated calls are useful when explicitly testing determinism or
caller ownership, rather than claiming independent correctness.

Mock external processes/network and expensive fixture providers where practical. Use inert local
executables for Make/process integration and refuse unmocked native/network work in synthetic tests.
Assert meaningful command properties and outputs, not exhaustive internal helper-call sequences.
Preserve rejection of failed builds, stale binaries, incomplete results and missing fresh evidence,
plus archive safety, process cleanup and failure propagation. Measure expensive tests before changing
setup or derivations; retain fixture ownership and reference/production independence. Remove tooling
only after checking Make, dispatches, dynamic discovery, documented CLI use and downstream consumers.

## Harness ownership

| Harness | Responsibility |
| --- | --- |
| `tests/test_verification_unit.py` | Unit/corpus completeness and separation from live E2E or Python discovery |
| `tests/test_verification_failures.py` | Independent family budgets, runtime rejection verdicts and failure-summary scope |
| `tests/test_verification_guards.py` | Exact compiler-fixture registration and compiler report completeness |
| `tests/test_verification_e2e.py` | Required E2E workloads, entry-point selftests and disjoint native identities |
| `tests/test_verification_python.py` | Fresh evidence and rejection of empty Python discovery |
| `tests/test_verification_profiles.py` | Shared compiler flags and isolated group caches |

These safeguards test the runners' contracts, not a second copy of every feature's totals.
They continue to exercise missing, duplicate and failed observations. Change a harness when its
own contract changes, not whenever an unrelated feature registers a suite or compiler probe.
All files are independently discovered by the existing Python verification command.

## Before opening a PR

Run `make check-inventory` for registration changes and the selected native suite or affected
Python harness/reference tests for local behavior changes. Broaden to an entire verification group
for cross-cutting changes or failures; CI retains complete verification. Documentation-only edits
need relevant lint/link checks, not a native rebuild. New tooling/test sources enter shared provenance automatically; preflight catches invalid inputs. Keep retained historical counts unchanged, and
report actual local results separately from CI status.
