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
fixtures continue to use the feature adapters and shared preparation described in
[infrastructure](infrastructure.md).

Compiler rejection sources belong under `tests/native/compile_fail/`, with one source-local header:

```nim
# @@Verification={"group": "privacy", "expected": "privateField"}
```

Groups are `privacy`, `nominal`, `contracts`, `schemas` and `ownership_compile`. Expected diagnostics
keep the runner's group-specific meaning: private member, nominal mismatch, violated precondition,
unsupported schema domain, or exact ownership-lowering error. Nominal `early` pairs retain the call
and positional diagnostic. Ownership declarations require a unique `build_name`; `offload: true`
retains the enabled proof-pool ABI/define. New rejection behavior may need an explicit predicate
in the guard runner; declaring a filename alone never makes an arbitrary compilation error pass.
Do not add fixture identities to a central registry or a new sidecar file. Discovery rejects missing
or invalid declarations before setup, and report checks reject missing, duplicate or failed results.

## Runtime failures and independent corpora

Add ordinary runtime probes to `tools/failure_suites/<family>.json`, one case per line, with
automatic alphabetical scheduling from those validated files. No runner edit or second family list is needed.
The declared cases supply expected identities before execution; never infer expectations from
observed results. Specialized drivers own typed enum cases tagged with `# @@ProbeCases` and expose
`--list-cases`; add their origin/diagnostic combinations to the specialized source-owned plan.
Preserve positive controls and intentional language-policy cases.

Independent expected values remain in `tests/` oracles. Corpus orchestration belongs in the
appropriate `tools/corpus_*.py` module; preserve request hashes, build profiles, complete output
comparison and explicit scheduling. Register a named `<feature>_corpus` callable with the owning
module's `@CORPORA.case`; return its verdict instead of separately assigning a report key. The
registration supplies both scheduling and completeness expectations. Preserve shared-build
dependencies in the feature/task order.

## E2E tasks and shared provenance

Declare E2E workloads and selftests as named `@PLAN.workload` and `@PLAN.selftest` callables in
`tools/e2e_checks.py`. Their names supply both scheduling and required report identities; return
verdicts instead of adding a parallel coverage list. Use ordered `@PLAN.setup` tasks for shared
peer builds. Keep resource limits, workload order and cleanup in the owning task. Direct offload
selftest callables are shared with the E2E plan through a context adapter.

Runtime, E2E and compiler-guard reports share `runtime_provenance.runtime_sources()` discovery.
New project modules, helpers and fixtures are included automatically; retain explicit pinned
upstream input contracts and generated-fixture hashes.

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
