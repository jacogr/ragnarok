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

The additional `check-docker` job builds and smoke-tests the [container image](containers.md)
on unit/full requests, retaining logs without publishing an image.

Each group writes `results.json` and diagnostic logs in its evidence directory. Use
`make summary-unit`, `make summary-failures`, `make summary-guards`, `make summary-python`,
`make summary-modules` or `make summary-e2e` to summarize completed reports. A missing report
is a failure, not evidence of coverage.

## Requesting CI

PR creation, pushes and stack rebases do not start CI. In the PR sidebar, add one label to
request verification of the current PR merge revision:

| Label | Requested checks |
| --- | --- |
| `ci:unit` | All native unit shards and codec corpora, Python references/tooling, source compilation, Docker build/smoke |
| `ci:e2e` | End-to-end networking tests only |
| `ci:full` | All verification groups, including compiler guards, runtime contracts and JAM Tart interoperability |

The label addition is the request; leaving a label on a PR does not enable automatic checks on
later commits. Remove and reapply the label to request checks after another push or rebase.
For stacks, request checks on the top PR when the combined changes are ready. For example:

```sh
gh pr edit <number> --add-label ci:full
# After a later push/rebase, request a fresh run with two separate commands.
gh pr edit <number> --remove-label ci:full
gh pr edit <number> --add-label ci:full
```

A new request cancels an older run for the same PR; unrelated labels schedule no runners and
cannot cancel requested checks. Results apply only to the tested revision. A focused run does
not claim the deferred groups passed. Master pushes/merges always request full verification;
newer master runs supersede older ones.

For standalone branch verification, use **Actions → CI → Run workflow**, select the branch and
choose `unit`, `e2e`, `docker` or `full` (the default). CLI equivalent:

```sh
gh workflow run ci.yml --ref <branch> -f suite=full
```

Use the PR labels when PR-associated checks are needed. Manual branch dispatch is separate
verification and may not satisfy required PR checks. If branch protection is introduced, require
only the intended scope: a focused request deliberately skips full-only groups, and intermediate
stack PRs may have no requested evidence. Local verification remains required before publishing.

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
Master CI and `ci:full` requests retain complete verification; focused local or CI results must
never be reported as a full pass.

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
