# Adding and changing verification

Feature PRs own their test sources, inventory entries and feature specification. Avoid adding
rolling global totals or feature-by-feature progress notes to the shared testing index. Record
coverage details and reproduction commands in the feature's `spec/` document instead.

## Native suites and compiler rejections

Add native application assertions under the appropriate `tests/unit/` directory with an explicit
`.output` contract. Register the suite in `tools/verification_inventory.json` and declare its
source directory, library order, observer flags and fixture requirements in
`tools/native_requirements/<source-family>/<suite>.json`. Keep independent inventory identities
and profile fields alphabetical, using the existing feature prefix; retain ordered link options.
Fixtures use the feature
adapters and shared preparation described in [infrastructure](infrastructure.md).

Register compiler rejection sources under `tests/native/compile_fail/` in the appropriate
`PRIVATE`, `NOMINAL` or `CONTRACTS` inventory, including their expected diagnostics. The compiler
coverage test compares registered identities with the actual fixture files, including the
explicit schema and ownership-lowering probes. Missing or duplicate registrations fail without
maintaining a second aggregate count.

## Runtime failures and independent corpora

Add ordinary runtime probes to `tools/failure_suites/<family>.json`, one case per line. Preserve
an independently declared family count in `FAILURE_COUNTS` and one explicit scheduler call in
`tools/test_runtime.py`. The family loader validates that count against the cases, and the
preflight checks scheduler/file agreement. Specialized families retain their explicit budgets
and code paths. Never derive a family's required count from the number of results it produced.

Independent expected values remain in `tests/` oracles. Corpus orchestration belongs in the
appropriate `tools/corpus_*.py` module; preserve request hashes, build profiles, complete output
comparison and explicit scheduling. Register new corpus identities in `CORPUS_NAMES`.

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
need relevant lint/link checks, not a native rebuild. Add new tooling/test sources to runtime
provenance; the preflight catches omissions. Keep retained historical counts unchanged, and
report actual local results separately from CI status.
