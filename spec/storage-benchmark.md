# Storage speed comparison

`Perf Storage` is grouped beside `Perf PVM` in CI. It compares memory `NodeRepository`, the
single-file `FileRepository` journal and managed `FileRepository` using existing public APIs.
It changes no backend defaults, storage format, recovery authority or checkpoint-import trust.

## Fixed checked workload

`make bench-storage` owns setup and builds `tests/performance/storage_workload.nim` with pinned
Nimony native ARC, Clang, release optimization, bounds checks and LTO, linking maintained crypto.
Each backend runs at 1,024 and 8,192 entries with 256-byte values. Prepared identical seed and
sixteen one-key deltas stay outside timing; every timed publication uses the public snapshot and
publish API. Disk publication includes actual synchronization; memory publication is not durable.

Separate phases measure 4,096 lookups cycling 128 unchanged leaf addresses, complete-map
extraction and strict durable reopen. Returned lookup payloads and every map entry/root/generation
are validated outside timing. Reads use resident repository views, including disk-backed views;
the workload does not measure cold/random disk reads or evict the OS cache. Memory has no durable
reopen and receives no invented timing. Seed creation, compaction, validation and cleanup are
excluded from timed phases. Each sample has a fresh exclusively created namespace.

Three validated warmups precede ten measured samples per backend/size. A second pass reverses
backend order, yielding twenty measured samples with min/median/max and visible noise flags.
There is no universal speed threshold or power-loss certification. Ratios are host observations,
not interchangeable durability guarantees or production throughput claims.

## Evidence and failure handling

`build/tests/storage-benchmark` owns `results.json`, `samples.csv`, `summary.md`, native build and
process logs. Reports record head/dirty state, source hashes, toolchain, crypto library hash,
platform/CPU architecture and load. Any assertion, IO refusal, build/process error, timeout or
missing/duplicate/invalid sample fails the command. Partial runs cannot produce a green table;
previous summary/CSV success is removed before execution. Timeouts retire the native process group.

`make summary-storage-benchmark SUMMARY_OUTPUT=...` works without setup and makes missing or
invalid reports visibly fail. The Actions job calls it with `$GITHUB_STEP_SUMMARY` under `always()`
and retains raw artifacts for thirty days. It runs on master pushes, `perf`/`full` dispatch,
`ci:perf`/`ci:full` labels, or storage-only `bench-storage` dispatch. No remote run is requested merely
by adding this job. Python safeguards cover complete coverage, invalid timing/unavailable reopen,
forged statistics, failed reruns and adjacency/trigger/summary/artifact policy.

## Local implementation verification

The complete checked benchmark produced 156 validated samples and all eight operation/size rows
on macOS ARM64. JSON, CSV and downloadable Markdown were generated; the setup-free summary
matched the runner's Markdown exactly. Forty-eight focused Python checks cover storage reporting,
failed-run/missing-report behavior, CI grouping/triggers/artifacts and existing PVM report behavior.
Verification inventory, workflow YAML syntax and whitespace checks pass. These local results do
not claim an Actions/Linux timing result; the CI job records its own host and source provenance.

## Key topology coverage

Each backend/size now runs both leading and trailing two-byte key identities. Trailing identities
share 232 additional prefix bits and exercise deep routing without changing the authored key/value
count or update semantics. Native output, JSON cases, CSV and Markdown retain the topology identity;
missing or mismatched shapes refuse comparison. All complete maps and individual read payloads
remain validated outside timing. The existing Perf Storage job stays adjacent to Perf PVM.

## Inline and out-of-line value coverage

Every backend, size and key topology now runs 16-byte inline and 256-byte out-of-line values.
Fixture identity includes the payload length in native samples, JSON, CSV and Markdown. Aggregation
revalidates that identity rather than accepting timings substituted from a cheaper representation.
The complete authored payload and exact selected root remain positive controls for every sample.

## Current-root reclamation

A separate phase selects and clones the current complete root in memory, or performs actual
managed compaction including file/namespace synchronization and predecessor retirement. The
journal layout has no equivalent operation and displays an explicit unavailable sentinel, with
no fabricated ratio. Root/generation, reclaimed records, header-only selected journal, strict
post-compaction restart and held pre-compaction maps are validated outside timing. The original
reopen phase remains before compaction so it still measures full journal admission.

## Bounded retained-history reclamation

A separate nine-root phase retains the seed and last eight prepared revisions, comparing memory
selection/clone with actual managed compaction. Every complete historical key/value map survives
strict managed restart. Current-only managed reclamation then runs against that selected epoch;
the selected root and generation never advance. Both phases preserve pre-compaction readers.
The journal layout remains explicitly unavailable. Synthetic revision retention supplies neither
block finality nor checkpoint trust, and fixture expectations are prepared outside timing.

## Physical work and selected-file extents

Raw samples and CSV retain stored/current record counts and actual selected snapshot/journal byte
extents before and after reclamation. A separate Markdown table explains the physical work behind
timings. The fixed fixture must have identical counters across all warmups, measured repetitions
and reversed-order passes. Memory file extents and unsupported post-compaction journal extents
remain unavailable; a legacy snapshot is exactly zero. Selected-file bytes exclude unknown or
staged files and graph memory retained by old readers, so they are not total resource usage.
