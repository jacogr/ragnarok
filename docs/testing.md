# Testing

Use `make check` (or `make test`) for the complete local verification path. Each group can also
run independently and provisions its own dependencies. `make check-inventory` provides the fast,
Python-only registration and provenance preflight used before every CI workload.

## Current verification groups

| Make target | Scope | Evidence directory |
| --- | --- | --- |
| `check-modules` | Every-source semantic compilation | `build/tests/modules/` |
| `check-python` | One Python reference, tooling and provenance discovery | `build/tests/python/` |
| `check-unit` | Discovered native suites and independent corpora | `build/tests/runtime/` |
| `check-failures` | Every declared runtime behavior/contract family and store positive controls | `build/tests/failures/` |
| `check-guards` | Compiler contract, privacy, nominal, schema and ownership rejection probes | `build/tests/guards/` |
| `check-e2e` | Peer-entry selftests and live networking/resource scenarios | `build/tests/e2e/` |

CI runs these groups independently on separate VMs, without a `needs` chain or duplicate Python
discovery. `make unit` is the quick native-only subset, `make runtime` aliases `check-unit`,
and `make modules` aliases `check-modules`. The additional `check-telemetry-interop-ci` target
builds the pinned JAM Tart collector and verifies interoperability, including failed handshakes
and restart/replay behavior; see [telemetry verification](../spec/telemetry.md).

Each group writes `results.json` and diagnostic logs in its evidence directory. Use
`make summary-unit`, `make summary-failures`, `make summary-guards`, `make summary-python`,
`make summary-modules` or `make summary-e2e` to summarize completed reports. A missing report
is a failure, not evidence of coverage.

## Focused local verification

Use `make unit SUITE=natural` (substitute any discovered suite name) to execute just that native
suite with the same pinned compiler, linking, fixture validation and selected-suite ARC checks.
Focused output is summarized; full runner diagnostics remain in
`build/tests/native/selected/<suite>.log`, with a bounded excerpt on failure. An unknown suite is
an error. `make unit` without `SUITE` retains complete native discovery. Shared setup still runs;
linked/prepared suites currently retain shared native/fixture preparation, but unrelated tests
and unrelated ARC observations are not executed or retired. Pure unprepared suites skip native
library and integration-fixture preparation entirely.

Choose checks from the changed behavior and affected consumers. Registry-only conflicts usually
need `make check-inventory` and the affected inventory/provenance tooling tests. History-only
reconciliation with an identical tree can reuse the explicitly recorded previous results.
CI continues complete verification; focused local results must never be reported as a full pass.

## Coverage and adding tests

Native suite identities are discovered from `tests/unit/`, with ARC declarations in their source
headers. Compiler rejections own their expectations in `tests/native/compile_fail/` headers.
Linking comes from native requirements. Runtime expectations come from existing failure-family
files and [specialized plans](../tools/failure_plans.py); [named corpus tasks](../tools/corpus_catalog.py)
supply both execution and expected report identities. The preflight checks source/output coverage and registration; report
verdicts reject missing, duplicate and failed observations. Completed reports and their summaries
provide observed totals for the exact revision under test. This guide deliberately does not
repeat rolling grand totals that unrelated feature PRs would all have to update.

- [Adding and changing verification](testing/adding-tests.md): registration and feature ownership.
- [Shared verification infrastructure](testing/infrastructure.md): runners, fixtures and provenance.
- [Native migration history](testing/migration-history.md): frozen increment records, historical
  counts, parity evidence and the original Linux confirmation.

Keep feature-specific coverage, reproduction details and limitations in the relevant `spec/`
document. Adding a native suite or rejection family should not require editing this index or
unrelated verification-group tests. Historical results stay tied to their recorded revisions;
local verification does not substitute for Linux CI.
