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

Each process emits thirteen validated calls. Sample zero is the cold call; the
first three calls are excluded from the ten-call reused median. Forward and reverse
engine orders remain separate. CPU and wall statistics remain separate, with raw
samples retained. Constructor cost is outside public call clocks and reported
separately. Our public prepared call includes fresh invocation memory, callbacks,
immutable publication and lease return. The reference call clock excludes its
restore and teardown; DOOM reference lifecycle measurements are shown separately.
These are explicitly scoped call comparisons, not complete application startup or
an additive decomposition of nested clocks.

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
matching measured revision/run identity and explicit attempt identity before
rendering. A pending, failed, missing or incomplete newest measurement is reported
as such; retrieval never silently substitutes an older successful revision. Explicit
historical run selection remains available through the helper's `--help` interface.
Downloading reports builds no toolchain and executes no guests.

Local behavioral tests cover scheduling and Make dependency expansion, complete
inventory, clock/policy/ratio validation, failure-safe publication, reference
selection and latest-report retrieval. Native Linux CI on both architectures is the
qualification for actual timing. A sub-resolution local CPU sample is a measurement
failure, not a value to floor, discard or relabel as wall time.
