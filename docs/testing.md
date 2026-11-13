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
| `check-guards` | Focused compiler regressions, ownership hazards and application admission boundaries | `build/tests/guards/` |
| `check-e2e` | Peer-entry selftests and live networking/resource scenarios | `build/tests/e2e/` |

**Model verification** runs as a separate step within **Build / Tooling** on master pushes
and unit/full requests, including after Python checks fail.
Its summary separates expected mutant/witness violations from base-model failures, and its
artifacts retain replayable models and full diagnostics.

CI runs these groups independently on separate VMs, without a `needs` chain or duplicate Python
discovery. `make unit` is the quick native-only subset, `make runtime` aliases `check-unit`,
and `make modules` aliases `check-modules`. The additional `check-telemetry-interop-ci` target
builds the pinned JAM Tart collector and verifies interoperability, including failed handshakes
and restart/replay behavior; see [telemetry verification](../spec/telemetry.md).
`check-mcp-interop` runs a hash-locked official SDK against the real peer and retains wire
transcripts; see [MCP verification](../spec/mcp.md#official-sdk-interoperability).

The **Build / Linux x86-64**, **Build / Linux ARM64** and **Build / macOS ARM64** jobs each
package and smoke-test their own [native archive](binaries.md). **Build / Docker** independently
builds and smoke-tests the [container image](containers.md) on the x86-64 Linux runner.
Master pushes, full requests and manual `build` requests run all four jobs. `ci:docker` and
manual `docker` requests run only the container check. Each job retains its own diagnostics;
the native jobs also retain their archive and checksum artifacts.

Each group writes `results.json` and diagnostic logs in its evidence directory. Use
`make summary-unit`, `make summary-failures`, `make summary-guards`, `make summary-python`,
`make summary-models`, `make summary-modules` or `make summary-e2e` to summarize completed reports. A missing report
is a failure, not evidence of coverage.

## Requesting CI

Master pushes and PR opening, reopening, source updates and adding `lgtm` automatically run **Build / Smoke**:
complete Nim/Rust formatting and unoptimized semantic compilation of every production module in one discovered
import graph, plus the real peer main with integration/offload enabled. Run `make check-smoke`
locally. Each named workload reports its own result, without separate aggregate jobs.
Automatic PR updates and manual
`smoke` requests select Smoke and Provenance. Master/full requests add Tooling and all four platform/container builds.
Linux x86-64 reuses native packaging setup for the checked-release every-source audit. Tooling
runs Python references, lifecycle model verification and compiler rejection guards, retaining separate
summaries/artifacts and independent failures. Smoke remains unchanged. Source audits apply no formatting and link no native libraries. `unit` / `ci:unit` requests select Smoke, Tooling and Linux Checks, preserving source/guard
coverage without adding binary packaging or Docker. Manual `build` selects Linux x86-64, Linux ARM64, macOS ARM64 and Docker.

On master and full requests, Provenance, Build, Tooling, Unit, Corpus and Contract are eligible
immediately. E2E, Interop, Perf and Fuzz become eligible when Smoke, the three platform builds and Docker
finish. Build failures still count against the workflow, and the second wave runs after
completion so its checks can report their own verdicts.

In the PR sidebar, add one label to request heavier verification of the current PR merge revision:

| Label | Requested checks |
| --- | --- |
| `ci:unit` | All native unit shards and codec corpora, Python references/tooling, source compilation, compiler rejection guards |
| `ci:e2e` | End-to-end networking tests, including official MCP SDK message exchange |
| `ci:interop` | All Interop jobs: PVM reference comparisons and JAM Tart interoperability |
| `ci:docker` | Docker image build and selftests only, without native archive packaging |
| `ci:perf` | All Perf jobs, including interpreted PVM and DOOM reference comparisons |
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

Unit and Contract use 15 and 5 shards respectively. Each run shuffles discovered work with its
shared GitHub run ID, without historical timing weights or maintained assignments. Unit batches
are first stratified by their unique transitive project-module count, spreading similarly weighted
work across shards before randomizing execution order. Reports and summaries retain the seed for
[local reproduction](testing/infrastructure.md). The dependency-ordered codec and specialized-control
bundles retain randomized shard ownership. Independent corpora run once across randomized
[`Unit / Corpus` shards](testing/infrastructure.md) alongside the unit shards. Producer/consumer
bundles stay together and retain declaration order, without timing weights. The Unit gate requires
every native and corpus shard to pass.
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
choose `smoke`, `unit`, `e2e`, `build`, `docker`, `interop`, `perf`, `ref-pvm`, `bench-pvm`, `bench-doom`, `bench-storage`, `bench-storage-growth` or `full`
(the default). `interop` runs all Interop jobs; `perf` runs all Perf jobs. The existing
`ref-pvm`, `bench-pvm` and `bench-doom` selections run their declared scopes.
**Perf / PVM** runs automatically after master merges on native Linux ARM64 and x86-64.
One current-source runner compares our public prepared interpreter and JIT with pinned PolkaVM
interpreted across all maintained synthetic micros, sieve sizes, minimal, memory fill, Pinky,
and separate DOOM initialization/gameplay. DOOM uses the canonical frame after 1,320 ticks;
its fixture identity is distinct from historical warmup-zero results.

The Actions summaries retain raw CPU/wall medians and interpreter/reference and JIT/reference
ratios, separately for both process orders. Constructors, cold calls, reused calls and reference
DOOM lifecycle costs retain their scopes. Every sample validates complete state/output and
source immutability; per-case native counters expose genuine JIT work or explicit checked fallback.
Missing or foreign evidence fails the job. Ratios are informational, with no noisy speed threshold.
See the [monitoring contract](../spec/pvm-ci-performance.md) for inventory and scope details.

Use `make pvm-perf-latest` to download and validate both reports from the newest master-push CI
run, with exact revision/architecture/coverage identities. It follows each CPU's latest actual PVM
execution across selective retries and shows its attempt separately from the overall CI conclusion.
It reports pending or failed newest PVM data rather than silently returning an older green result.
No toolchain or benchmark runs during retrieval. JSON, CSV, summaries and logs remain available as
architecture-specific Actions
artifacts for 30 days.

A manual `bench-pvm` workflow request runs the same complete PVM path without Storage or unrelated
CI groups; `bench-doom` selects only DOOM. Both default to ARM64 and x86-64. Their optional
`pvm_architecture` input selects one CPU for focused qualification. Ordinary `perf`/`full` and
master requests always include both. Historical profile/replay/calibration and pricing/revision
commands remain explicit Make diagnostics; they are not alternate CI performance paths.

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
`bench-storage-growth` selects growth and SDK controls. Both dispatches use the **Perf / Storage**
name. Group requests run comparison, resource panels, memory ceilings and growth sequentially on
one Storage runner, reusing installed tools and the Rust provider build. Growth still runs after an
earlier panel failure unless cancelled; any failed step keeps Perf red. Each panel always renders
its own summary and retains its separate JSON, CSV, Markdown and logs, including failures. Timing has
no fixed CI speed threshold. See [the workload contract](../spec/storage-benchmark.md) for scope.
