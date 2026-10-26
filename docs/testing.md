# Testing

Use `make check` (or `make test`) for the complete local verification path. Each group can also
run independently and provisions its own dependencies. `make check-inventory` provides the fast,
Python-only registration and provenance preflight used before every CI workload.

## Current verification groups

| Make target | Scope | Evidence directory |
| --- | --- | --- |
| `check-models` | Bounded lifecycle safety, guard mutants and reachability with pinned tlanif | `build/tests/models/` |
| `check-modules` | Every-source semantic compilation | `build/tests/modules/` |
| `check-python` | One Python reference, tooling and provenance discovery | `build/tests/python/` |
| `check-unit` | Discovered native suites and independent corpora | `build/tests/runtime/` |
| `check-failures` | Every declared runtime behavior/contract family and store positive controls | `build/tests/failures/` |
| `check-guards` | Compiler contract, privacy, nominal, schema and ownership rejection probes | `build/tests/guards/` |
| `check-e2e` | Peer-entry selftests and live networking/resource scenarios | `build/tests/e2e/` |

**Model verification** is a separate visible CI job on master pushes and unit/full requests.
Its summary separates expected mutant/witness violations from base-model failures, and its
artifacts retain replayable models and full diagnostics.

CI runs these groups independently on separate VMs, without a `needs` chain or duplicate Python
discovery. `make unit` is the quick native-only subset, `make runtime` aliases `check-unit`,
and `make modules` aliases `check-modules`. The additional `check-telemetry-interop-ci` target
builds the pinned JAM Tart collector and verifies interoperability, including failed handshakes
and restart/replay behavior; see [telemetry verification](../spec/telemetry.md).

The additional `check-docker` job builds and smoke-tests the [container image](containers.md)
on master pushes, full requests and manual `build`/`docker` requests, retaining logs without publishing an image.
The Build group also checks [downloadable binary archives](binaries.md) on Linux x86-64 and macOS ARM64.

Each group writes `results.json` and diagnostic logs in its evidence directory. Use
`make summary-unit`, `make summary-failures`, `make summary-guards`, `make summary-python`,
`make summary-models`, `make summary-modules` or `make summary-e2e` to summarize completed reports. A missing report
is a failure, not evidence of coverage.

## Requesting CI

Master pushes and PR opening, reopening and source updates automatically run **Compile / Smoke**:
complete Nim/Rust formatting and unoptimized semantic compilation of every production module in one discovered
import graph, plus the real peer main with integration/offload enabled. Run `make check-smoke`
locally. The **Compile** aggregate requires this Smoke job on automatic PR updates and manual
`smoke` requests; master pushes and `unit`/`full` requests additionally require Source,
Reference & Tooling, and Rejection Guards. No formatting is applied and no native libraries are
linked. Master/full/unit source audits use the same complete graph with their checked-release profile.

In the PR sidebar, add one label to request heavier verification of the current PR merge revision:

| Label | Requested checks |
| --- | --- |
| `ci:unit` | All native unit shards and codec corpora, Python references/tooling, source compilation, compiler rejection guards |
| `ci:e2e` | End-to-end networking tests only |
| `ci:interop` | All Interop jobs: PVM reference comparisons and JAM Tart interoperability |
| `ci:perf` | All Perf jobs: the validated interpreted PVM speed comparison |
| `ci:pvm-compare` | Opt-in baseline/candidate, identical-source control and pinned PolkaVM real guests on one runner |
| `ci:full` | All verification, Interop and Perf jobs |

The label addition is the request; leaving a label on a PR does not enable automatic heavy checks on
later commits. Remove and reapply the label to request checks after another push or rebase.
For stacks, request checks on the top PR when the combined changes are ready. For example:

```sh
gh pr edit <number> --add-label ci:full
# After a later push/rebase, request a fresh run with two separate commands.
gh pr edit <number> --remove-label ci:full
gh pr edit <number> --add-label ci:full
```

Unit and Contract use 16 and 6 shards respectively. Each run shuffles discovered work with its
shared GitHub run ID, without historical timing weights or maintained assignments. Unit batches
are first stratified by their unique transitive project-module count, spreading similarly weighted
work across shards before randomizing execution order. Reports and summaries retain the seed for
[local reproduction](testing/infrastructure.md). The dependency-ordered codec and specialized-control
bundles retain randomized shard ownership. Independent corpora run once across three randomized
`Unit / Corpus (i/3)` jobs alongside the unit shards. Producer/consumer bundles stay together and
retain declaration order, without timing weights. The Unit gate requires every native and corpus
shard to pass.
Local `make check-unit` still runs both; `make check-corpus` selects only independent corpora.
Fuzzer-interface corpora and socket/minifuzz exchanges belong exclusively to `Fuzz / JAM`.
They run through `make check-jam-fuzzer-interface`, also included once in complete `make check`;
Unit and E2E do not repeat them. JAM fuzz uses two randomized native-corpus partitions and one
socket/minifuzz partition, with every partition required by the Fuzz gate. Native Unit and
Contract matrix checks use `Test (i/n)` display names.

New smoke updates cancel older smoke runs for that PR, without cancelling labeled heavy CI.
A new heavy request cancels an older heavy run for the same PR; unrelated labels schedule no runners and
cannot cancel requested checks. Results apply only to the tested revision. A focused run does
not claim the deferred groups passed. Master pushes/merges always request full verification;
newer master runs supersede older ones.

For standalone branch verification, use **Actions → CI → Run workflow**, select the branch and
choose `smoke`, `unit`, `e2e`, `build`, `docker`, `interop`, `perf`, `ref-pvm`, `bench-pvm`, `compare-pvm`, `profile-pvm`, `bench-storage`, `bench-storage-growth` or `full`
(the default). `interop` runs all Interop jobs; `perf` runs all Perf jobs. The existing
`ref-pvm` and `bench-pvm` selections remain available for individual PVM jobs.
**Perf / PVM** also runs automatically on master pushes. Its validated interpreted
[PVM speed comparison](../spec/pvm-benchmark-comparison.md) appears in the Actions
run summary with raw artifacts, so no manual dispatch is needed after a merge. The same job also
runs the frozen real-guest comparisons: sieve at 1k, 10k, 100k and 10 million; minimal
indirect calls; memory fill; and one initialized Pinky NES frame. Each
compares Ragnarök dynamic/complete-plan/lazy-memo execution with PolkaVM interpreted on
the same runner. Tables include median ratios, CPU variability, wall medians and scoped
pricing/first-execution costs; common module loading is excluded. No compiled backend or
additional VM is measured. Guest JSON/CSV, summaries and diagnostic logs are retained
with the synthetic workload evidence; fixture binaries and build caches are excluded.
See [the real-guest contract](../spec/pvm-sieve-benchmark.md). CLI equivalent:

```sh
gh workflow run ci.yml --ref <branch> -f suite=full
```

For revision experiments, add `ci:pvm-compare` to an open PR. **Perf / PVM Revisions**
checks out the exact PR head and compares against its exact base SHA; this job is the exception
to ordinary PR checks using the merge revision. It runs the paired seven-input/all-policy matrix,
plus paired synthetic host/memory/tiny controls, then an identical-source control, then the
pinned PolkaVM interpreted real-guest comparison,
sequentially on one Ubuntu 24.04 runner. Builds finish before each measured matrix. Raw state-checked
samples, endpoint/compiler/input hashes, CPU identity and separate summaries are retained for 30 days.
Noise controls and repeated runs qualify small differences; a fresh VM does not guarantee identical
physical CPUs across jobs. No speed threshold makes a noisy run pass or fail; semantic or identity
failures still fail the job. This experimental job is excluded from ordinary `perf`, `full` and
master requests. Manual requests accept `pvm_compare_base` as a local ref in the fetched history:

```sh
gh workflow run ci.yml --ref <branch> -f suite=compare-pvm -f pvm_compare_base=<baseline-sha>
```

The manual `profile-pvm` choice runs checked Linux Callgrind diagnostics separately
from timing jobs. It attributes native execution instructions on one state-checked
invocation per selected guest/policy; instrumented clocks establish no speed claim.
Use `make profile-pvm-guests` on a provisioned Linux x86-64 host with the pinned
Valgrind tools. See [the profile contract](../spec/pvm-instruction-profiles.md).

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

## Storage performance

`make bench-storage` compares memory, synced journal and managed repositories using the same
prepared batches, read requests and complete maps. `make summary-storage-benchmark` appends its
table to `SUMMARY_OUTPUT` and saves downloadable `build/tests/storage-benchmark/summary.md`.

In Actions, **Perf / Storage** sits beside **Perf / PVM**. Master pushes, `perf`/`full` dispatch and
`ci:perf`/`ci:full` PR requests run the group. `bench-storage` dispatch selects comparison/resources;
`bench-storage-growth` selects the independent Perf / Storage Growth matrix and SDK controls.
Each job always renders a summary and retains JSON, CSV, Markdown and logs, including failures. Timing has
no fixed CI speed threshold. See [the workload contract](../spec/storage-benchmark.md) for scope.
