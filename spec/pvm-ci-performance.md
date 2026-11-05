<!-- Copyright (c) 2026 Ragnarök contributors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# PVM CI performance monitoring

## One current-source comparison

**Perf / PVM** runs on native Linux ARM64 (`ubuntu-26.04-arm`) and x86-64
(`ubuntu-26.04`) on every master push, manual `perf`/`full` request and open-PR
`ci:perf`/`ci:full` request. Ordinary PR updates run Smoke only. Both architecture
jobs use `make bench-pvm-performance` and the same runner, workload inventory and
versioned report. Storage performance is independent. New master pushes retain
CI's existing cancellation policy, superseding unfinished older revisions.

The manual `bench-pvm` scope runs the complete PVM cohort without Storage or
unrelated CI groups. `bench-doom` selects its DOOM subset. Both default to the two
architectures; `pvm_architecture` can select one native CPU for these focused
requests. Partial reports identify their scope and cannot satisfy complete
master-report retrieval. Native CI diagnostics may select `PVM_PERF_SCOPE=micro`
through the same Make target. Profiling, calibration, retained-core, replay and
historical pricing/revision tools remain explicit Make diagnostics, outside this
CI measurement path. Their former `jit-*` CI dispatch choices and optional previous
baseline inputs are retired.

## Workloads and engines

The complete inventory composes the maintained eleven synthetic micro workloads,
sieve at 1k/10k/100k/10 million, minimal and memory fill at 1k/100k, one initialized
Pinky frame, and separate DOOM initialization/gameplay calls. The three engines are
current public prepared execution with forced interpreted policy, the same current
production image with JIT policy, and pinned PolkaVM interpreted. Native compiler
and reference source pins are unchanged. No standalone native backend, historical
baseline or retained-core timing substitutes for a current public call.

The synthetic harness records genuine process CPU and wall nanoseconds. Historical
wall-only observations are never relabeled CPU. All native policies use production
architecture flags and the checked ARC/Clang ThinLTO profile; native-host
qualification must pass before timing. The declared runner, actual uname/Python
architecture, native compiler archive and measured source must agree.

DOOM uses the canonical 1,320-tick prepared gameplay state and upstream rendered-frame
golden, with independent initialization and tick fixtures. The warmup count, guest,
WAD, expected state and event hashes identify this cohort. Historical warmup-zero
comparison results are a different workload. Complete CPU, gas, PC, paid state,
registers, final page layout/permissions/bytes, source snapshots and ordered host
output are checked outside clocks. Assertion/state/event refusal controls and
source/fixture identity checks remain required. Expected results are never generated
by the measured candidate.

## Measurement and reporting

The `pvm-performance-v2` cohort binds `code_lifetime=retained-code-v1`. Each case
retains one prepared owner on our side and one actual PolkaVM interpreter instance
on the reference side. Invocation memory, all thirteen registers, gas, PC and host
progress are reset for every call. Public `reset_memory` preserves the reference's
lowered-code cache; no private hooks or interpreter-cache reset are used.
The former v1 reference created a fresh instance for every sample. Those historical
ratios are a different lifecycle cohort, not evidence of a source-code speedup when
compared with v2. Latest retrieval accepts only the current schema and never mixes
the two cohorts or silently substitutes an older result.

Each process emits thirteen validated calls. Sample zero is the cold call; the
first three calls are excluded from the ten-call reused median. Forward and reverse
engine orders remain separate. CPU and wall statistics remain separate, with raw
samples retained. Constructor cost is outside public call clocks and reported
separately. Our public prepared call includes fresh invocation memory, callbacks,
immutable publication and lease return. The reference call clock excludes its
invocation restore. One-time reference instance construction/destruction and
per-call restore CPU/wall clocks are retained separately for every workload family.
The reference still does not publish immutable memory snapshots inside its call;
retained code aligns code lifetime, not all embedding capabilities or timing scopes.
These are explicitly scoped call comparisons, not complete application startup or
an additive decomposition of nested clocks.

Cumulative observations sum public-call samples zero through twelve, including
samples one/two and delayed work. Every call prefix retains integer CPU and wall
totals separately by engine and process order. The all-thirteen-call table shows
totals and ratios, the first observed JIT/interpreted break-even call count, whether
that crossing holds through call thirteen, and any later crossing that does hold
through the observed window. Break-even includes equality; reuse count is call
count minus one. A missing crossing remains unobserved. These observations neither
establish steady state nor predict a future crossover. Constructor and reference
lifecycle scopes remain separate; cumulative totals use the existing call clocks.

Every reference case emits exactly one `REFERENCE_INSTANCE,1,label,cpu,wall,cache`
and one `REFERENCE_INSTANCE_DROP,1,label,cpu,wall`, surrounding thirteen ordered
`REFERENCE_RESTORE,1,label,sample,cpu,wall` and
`REFERENCE_CACHE,1,label,sample,before_reset,after_reset,after_run` pairs. Initial
cache size must be zero. Each later entry must equal the preceding completed cache;
the complete memory/ABI restore must preserve that size, and execution must leave
a positive, nonshrinking cache. Per-sample receipts follow the corresponding complete
state/event checks before acceptance. Constructor receipts validate the new empty
cache before any call; destruction follows the complete case. Missing, recreated, warmed-outside-call or
reset caches cannot qualify as a retained instance. Subsidiary constructor/restore/
destruction clocks may legitimately report zero observed ticks at clock resolution;
no floor is applied, and execution CPU/wall clocks remain strictly positive.

CSV rows retain actual per-call restoration clocks and cache sizes. Restore includes
its preflight and read-only-page comparisons; the separate complete input/final-state/
event oracles remain outside these clocks. Explicitly named restore-plus-call sums
exclude those complete oracles and one-time construction/destruction; they are not
whole-process timings. One final instance destruction is
never duplicated into thirteen per-call teardown observations. Unobserved module
constructor clocks remain absent rather than becoming zero.

Tables show both current interpreter / PolkaVM interpreted and current JIT /
PolkaVM interpreted ratios, with lower values meaning less time. Requested policy,
actual completed native work, availability and counters accompany each workload.
A JIT request which executes no native operations is an explicit interpreted
fallback cell. Eligibility-based native coverage requirements cannot be satisfied
by unrelated workloads. Source/backend/clock/sample/coverage failures fail the job;
there is no noisy universal speed threshold or cross-architecture timing ratio.

The canonical JSON validates the exact configured workload/engine/order/sample
matrix, actual native policy, source and host identities before success. Summary
and CSV rendering precede atomic passed publication. Exceptions preserve current
failed evidence and cannot expose an old green table. Per-architecture artifacts
`pvm-performance-<architecture>-<attempt>` retain JSON, CSV, summaries and logs for
30 days, including failure diagnostics; executable images, compiler caches,
private experiments and fixture memory are excluded.

## Retrieve current results

`make pvm-perf-latest` uses authenticated `gh` to locate the newest master-push CI
run and retrieve both native architecture reports. It validates complete scope,
matching measured revision/run identity and each architecture's latest actual PVM
job execution before rendering. Selective retries may leave the two CPUs on different
attempts; both actual attempts remain explicit. Retrying an unrelated job does not
discard valid measurements. A newer failed, cancelled, skipped or incomplete PVM
execution blocks retrieval; an older green execution cannot replace it. The workflow
must finish, and its overall conclusion is shown separately from PVM validity.
The concrete job identity comes from the source-bound report, so display-name changes
need no duplicated selector update. Retrieval never silently substitutes an older
successful revision. Explicit
historical run selection remains available through the helper's `--help` interface.
Downloading reports builds no toolchain and executes no guests.

Local behavioral tests cover scheduling and Make dependency expansion, complete
inventory, clock/policy/ratio validation, failure-safe publication, reference
selection and latest-report retrieval. Native Linux CI on both architectures is the
qualification for actual timing. A sub-resolution local CPU sample is a measurement
failure, not a value to floor, discard or relabel as wall time.
