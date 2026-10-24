# Maintained real-sieve interpreter comparison

`make bench-pvm-sieve` runs the checked-in upstream prime-sieve guest on Ragnarök and pinned
PolkaVM's **Interpreter**, JamV1, synchronous Full/L2Hit gas profile. Ragnarök runs
dynamic, optional [complete plans](pvm-gas-plans.md) and [lazy memos](pvm-gas-memos.md), with complete state checks in each mode. It builds the host runners
through normal setup; it installs no historical guest compiler and invokes no compiled backend.
The existing `make bench-pvm` eleven-workload comparison remains separate; its frozen guests are unchanged.

The frozen guest and complete source/compiler/linker/license record live in
[the fixture directory](../tests/fixtures/pvm-sieve/README.md). A checked export returns the prime
count and validates it inside the guest. This extra export means the result is not a published
stock upstream benchmark score. Every fixture member and recorded upstream source is hash checked,
and the host Cargo lock must introduce no package identity absent from the pinned upstream lock.

## Measurement and correctness contract

The maintained sieve sizes are 1,000, 10,000, 100,000 and 10,000,000, with independent
known prime counts 168, 1,229, 9,592 and 664,579.
Untimed public PolkaVM preparation freezes the initial machine and complete expected result.
Both measured runners consume these immutable files; neither regenerates expectations during a
measurement. They compare final gas, all thirteen registers, and every mapped page byte outside
timing, plus the independent prime count. Ragnarök additionally checks terminal PC, charged-block
state, deficit, access permissions and preservation of the original CPU/page snapshot.

Each engine/pricing mode runs thirteen fresh executions per pass: three warmups and ten measured observations.
Two passes reverse engine order. Both process CPU and monotonic wall time surround execution only;
module decoding, instance creation and full state validation remain outside the interval. Strict
sample framing rejects missing, reordered, duplicate, foreign and nonpositive rows. Process CPU is
the primary summary metric; all raw CPU/wall observations, including warmups, remain in CSV/JSON.
Differences between pass medians above 25%, or a central sample spread above 2x, flag noise without
removing observations. This is not host isolation or a statistical significance claim.

Planned mode additionally emits one strict preparation record with CPU/wall duration, code bytes,
block count, table payload and fixed cycle ceiling. Both process orders and every guest size must
agree on resource identity. The summary shows preparation and reuse amortization separately. Memo mode additionally requires
a final bounded occupancy witness and shows first-cold execution alongside initialization, because
that first execution performs lazy pricing. A cold invocation pays those costs before reuse helps.

Before measurement, each engine/pricing mode must fail its assertion sentinel, reject a
truncated initial machine, and reject a corrupted expected register. Every measured invocation
checks frozen input hashes before and after execution. Build/process errors or invalid observations
fail the complete command, replace its verdict, and remove stale successful sample downloads.

Outputs are `build/tests/pvm-sieve/{results.json,samples.csv,summary.md}` with retained build/control/
execution logs, source and binary hashes, guest pins, build commands, toolchain versions, host/CPU
identity, load averages and explicit build environment flags. No hostname or unrelated environment
is collected. The Perf PVM job runs this command and the frozen guest pack on master pushes and
existing `perf`/`bench-pvm`/`full` requests. Ordinary correctness and Smoke checks do not
run timed workloads. The same runner compares only Ragnarök pricing modes and PolkaVM
interpreted; compiled backends and prepared experiments remain outside this job.

## Local evidence and limits

On Apple M1 Max/macOS with checked ARC/Clang ThinLTO, initial maintained-run CPU medians were
0.598 versus 0.494 ms at 1,000 and 20.746 versus 6.168 ms at 100,000 (Ragnarök versus interpreted
PolkaVM). These are local observations, not exact-head Linux CI or general performance claims.
The remaining real-sieve gap is roughly 3.4x on this machine. Keep measuring production execution
and reject optimizations whose correctness or representative workload cost outweighs their gain.

M1 framing is implemented in its documented scope; complete state serialization and full JAM/STF
execution remain open. Fuzzing remains deferred pending maintainer Daybreak access.

The same maintained adapters also serve the separate [real-guest pack](pvm-real-guests.md),
which adds indirect calls and memory fill at two checked sizes. Each new process carries an
explicit family witness; the default sieve command keeps its existing framing and fixture.

## Pinky and CI report scope

`make bench-pvm-guests` also includes the independently frozen
[Pinky NES fixture](../tests/fixtures/pvm-pinky/README.md), preserving the existing minimal
and memory-fill controls. Pinky uses the unchanged pinned upstream emulator and ROM;
its checked call renders one frame with ABGR conversion from a frozen initialized NES
state. Nine initialization frames run untimed in the public reference adapter before
input capture. Both interpreters receive that exact initialized memory; the reference
restores writable pages into a fresh instance before each call. Gas/registers are reset
to the same explicit input, and read-only pages retain their original permissions.
These metered, checked runs are not directly comparable to upstream published scores.
Both interpreters compare all mapped memory (including framebuffer/NES state), gas and
registers. Returning one proves completion of the checked call, not an independent proof
of NES emulation. A separate descriptor binds the artifact, checked entry, package/ROM
pins, normalized manifests, lock and license notices without changing earlier artifacts.

The report shape follows the useful comparison dimensions in
[PolkaVM's benchmark report](https://github.com/paritytech/polkavm/blob/master/BENCHMARKS.md):
execution times, variability and relative speed. It retains median CPU ratios plus CPU
mean/sample standard deviation, min–max and wall median for every interpreted mode. A
separate first-execution table includes pricing initialization for complete/lazy modes;
common program/module loading, host compilation and process startup are excluded. It is
not an end-to-end compilation/initialization score or a comparison to published numbers.
All raw observations and noise flags remain available. No speed threshold fails CI;
identity, correctness, assertion, malformed-input and complete-report failures do.
