# One checked handler-stream interpreter

## Scope and authority

The application has one opcode execution engine in `src/pvm/internal/handler_stream.nim`.
`src/pvm/step.nim` provides guarded immutable-snapshot, single-step and host adapters. The prior
instruction evaluator, decoded-instruction spill, dynamic block-price replacement hierarchy and
LRU prepared-segment engine are removed. Optional complete/lazy price owners remain pricing
policies over the same engine, rather than separate opcode implementations.

Gray Paper commit `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, recorded vectors and existing scoped
PVM discrepancy decisions remain authoritative. Dependency/compiler pins, arithmetic semantics,
checked memory ordering and runtime assertions/bounds checks are unchanged. Execution organization
was informed by the pinned PolkaVM interpreter; instruction semantics, unsigned accounting and
JAM-specific boundaries use our implementations. This change does not enable guest compilation.

## Ownership and API

The ordinary `execute`, scoped stepping, `applyHostResponse` and response-only/fallible
`executeWithHost` signatures remain available. All instruction mutation passes through the new
engine. The scoped APIs select their capability before affordability and adapt the same engine's
PC to Psi_1. Recursive panic/halt normalize PC zero; a single trap advances by its original skip,
other single terminal instructions retain the causing PC, and single host suspension advances
while recursive host suspension retains its causing PC. Invalid imported terminal PCs still
produce recursive uncharged deblob panic; single stepping rejects them locally.

A prepared owner retains immutable source/facts plus an exclusive executable cache. The cache
contains handler pointers, sealed scalar operands, source sites, stable offset maps and preparation
counters. It contains no CPU, guest memory, paid gas, callback or invocation continuation. A call
moves that cache into a newly admitted private frame and moves only cache facts back after success
or local failure. Same-owner synchronous reentry returns `PreparedProgramBusy`; independent owners
can nest. The lease is released on all returned failure/success paths. There is no owner back-edge.

Memory construction accepts a genuine immutable `Memory`, checks its page count before copying
page images, and retains that original root rather than recapturing it. Mutable contiguous regions
and fragmented slow-path regions remain private to the invocation. Host suspension publishes an
immutable observation; checked resident deltas resume the same frame. Mapping/permission changes
use complete transactional re-admission. Host terminal replies retain the causing PC, and fallible
callbacks preserve the original selected enum reason. Attempt and callback budgets span the whole
outer invocation. Local refusal never exposes a successful partial machine.

## Explicit resource migration

The removed LRU cache's `PreparedByteLimit` / `PreparedBlockLimit` policy no longer exists.
`PreparedLimits` now contains `resources: ExecutionLimits` and `cycles: GasCycleLimit`.
`defaultPreparedLimits(cycles)` selects the current finite profile; applications may copy it and
choose smaller component limits before `newPreparedProgram`. Invalid/default preparation results
publish only a reason. `preparedInfo` returns copied code/fact/node/work diagnostics and the policy.

Default and currently supported code/fact limits are 4,194,304 each; jumps and mapped pages are
bounded by 1,048,576. Default emitted nodes are bounded by 8,388,608 (representation maximum
2,147,483,646), and cumulative preparation source-span reservations by 67,108,864. The source-span
allowance reserves suffix length plus containing-price-block length before emission/pricing.
It is separate from guest gas, source attempts and each pricing call's cycle limit.

Stable offsets are never recycled or evicted during a call. A whole suffix must fit before its
first node/map write; cached entries remain usable at a full budget. New suffix refusal is sticky
with that cache and returns local `InvalidPreparedProgram`, never a guest panic/out-of-gas or a
successful partial snapshot. Reconstruct an owner to choose a different policy. Zero attempts
retain ordinary `StepLimitExceeded`. Admission is atomic per suffix, not per conditional graph.

These are logical component bounds, not exact RSS, allocator-overhead or global concurrency quotas.
The four-MiB implementation profile is not a consensus module-size rule: larger inputs fail local
admission and require a separately qualified profile. Environmental allocator failure remains fatal
under the existing runtime policy; it is not translated into a guest exit. Applications continue to
own the number/lifetime of live invocations and prepared owners.

## Qualification and timing boundaries

The ten stream witness groups now live under `tests/unit/codec/test_pvm_stream_*` with ordinary
source-owned requirements/output discovery. They preserve full opcode, aliases, budgets, high gas,
source snapshots, host repair, fragmented mappings, publication epochs, dirty bitmap boundaries,
resource refusal and cache/source binding checks. Existing single-step, execution, prepared,
pricing, host, independent frozen-reference and state/inner-machine consumer checks also qualify
public adapters. AddressSanitizer uses the maintained calibrated runner, including intentional
positive/heap/stack controls, all promoted stream groups and public execution/host suites.

The second-layer Linux run [40452151944](https://github.com/jacogr/ragnarok/actions/runs/40452151944)
compares measured head `e1bccc7372b284868d50b3ba1e6461f5fcb91969` with exact master
`5de8efcb0a1bcd16dcc5bc596b56c6dedd691bf0` and pinned PolkaVM interpreted on AMD EPYC 7763.
All 36 processes / 468 checked calls, 54 controls, eight fresh repeat builds and six independent
DOOM admission controls passed. It measures the experimental core, not this integration's public
API. The original full tables and evidence are linked from PR #1720. It shows major master gains
but no uniform Linux lead over PolkaVM, and material process-order variation remains visible.

Public default APIs create invocation-local preparation/private memory inside their call; retained
prepared APIs prepare source facts outside calls but still construct private invocation memory.
The direct-engine benchmark can retain a frame across calls. Those boundaries are different and
must not be presented as identical performance. The regular PVM and DOOM CI comparisons measure
the integrated public APIs and retain full-state checks; they must qualify this exact integrated
head separately. Constructors, cold/reused calls, reset and publication remain distinct in reports.

## Completion evidence

Local qualification passed the promoted ten native groups, existing stepping/execution/prepared,
complete/lazy pricing, host logging/response/failure, independent mixed/control/memory/jump/register
references, metered retry, inner invocation and accumulation invocation suites. Calibrated ASan
passed all 19 selected suites and three positive/heap/stack controls. Complete DOOM initialization
and gameplay passed through the public API, including all six refusal controls. Final formatting
and the smoke import graph passed all 452 production modules and the peer entry point.

Integration qualification also confirmed and fixed a lazy-price compatibility regression: merely
preparing a paid or untaken suffix must not populate the caller's observable GasMemo. A focused
prepaid-entry witness fails before the fix and passes after it; the independent conditional-control
corpus also passes with exact entered-block memo occupancy. Memo queries now occur only on actual
unpaid entry, then use the normal cached header. This adds no per-opcode query.

Legacy opcode-injection Make targets tied to the deleted evaluator are retired. Their historical
evidence parsers remain strict, and attempting to inject into the current engine fails explicitly;
source-attempt/stream counts must not be presented as native or hardware measurements.

The full local Python discovery exercised 1,519 cases (two skips). Its retained result is failed:
two historical-injection tests had imported their earlier fixture before that fixture was corrected.
Both affected modules then passed all ten tests on the corrected tree, alongside 74 focused CI,
sanitizer, report and tooling checks. CI must independently qualify the published head; this is not
a claim that the original discovery receipt passed.

The incoming tooling PR #1723 replaces a roughly 1 MiB decoded-spill constructor temporary with
direct heap allocation. This integration deletes that entire spill structure. A local ARM64 size
probe using the unchanged pinned compiler measured FlatFrame at 2,544 bytes, MachineInfo at 136
and PageImage at 4,104; instruction/fact/region storage is heap-backed. These are inline type sizes,
not measured peak call-stack usage or evidence for a different compiler/architecture.

Exact-head Linux production-API comparisons are pending. No Linux production-API speed claim is
made until those measurements complete. This replaces the interpreter only; it does not claim
complete JAM/client readiness or change existing independent protocol discrepancy gates.

## Lab retirement

The integration removes the complete experimental directory, including bulky sample/probe JSON,
rejected patches, duplicate witness sources, overlay shim and standalone runner. The concise
[findings and provenance](pvm-interpreter-findings.md) retain measured scope and exact recovery
coordinates. Ordinary native/sanitizer suites own the promoted checks. Maintained lifecycle and
DOOM drivers live in `tests/performance/`; `make bench-pvm-interpreter` uses the production core
through `tools/pvm_interpreter_compare.py`. This cleanup changes no runtime implementation,
measurement scopes or complete-state/refusal predicates.

Cleanup verification passed 50 comparison/CI tooling tests, source inventory and pinned formatting.
Both relocated drivers compile through the ordinary and canonical snapshot import paths. Full
sieve/gameplay snapshots and both assertion-refusal controls pass through the relocated binaries;
production PVM sources are byte-identical to the pre-cleanup integration commit.

PVM Sanitizers is a family of the existing Unit matrix, alongside native suite and corpus
partitions. The shared Unit aggregate requires every family, and the same matrix artifact
retains sanitizer calibration, source/image identities and ARC evidence. There is no separate
sanitizer job when Unit is not requested. The scheduling and refusal safeguards pass locally.

## Bounded single-instruction adaptation

Linux Unit qualification exposed a genuine integration cost: the large execution-cache witness
stepped a long program instruction by instruction, and the adapter re-admitted the complete source
on every attempt. The unchanged 180-second codec deadline expired. This is not treated as a runner
failure, and neither the witness nor its deadline is reduced.

Scoped stepping now seals one genuine instruction into a private adapter plan. It uses the same
charge, arithmetic, comparison, checked-memory, static-control and host workers as ordinary
execution. Dynamic control specializes that same worker to query the selected original table
ordinal instead of preparing the full table. Scalar successor nodes end the one-attempt call;
no successor block is prepared or executed. The ordinary executor explicitly rejects adapter
plans. Prepaid stepping skips unused pricing, while unpaid entry still prices its whole genuine
containing block. Exact source ownership, capability-before-affordability, gas, faults and Psi_1
exit-PC rules remain unchanged. There is no second opcode evaluator or global cache.

A source with 17,001 instructions admits exactly one fact for a prepaid interior step, checks the
posterior PC/registers and retains the unchanged source. The original large execution-cache suite
and its 1,000-cycle ARC observation pass locally. Eleven selected native suites, all 19 calibrated
sanitizer suites plus three controls, pinned formatting and the production smoke graph pass on
this bounded-step implementation. Exact-head Linux qualification remains required.

## Integrated public API checkpoint and merge hold

[Run 40460762602](https://github.com/jacogr/ragnarok/actions/runs/40460762602) at
`f881eca200d045884dfe2c8772bd7d7fc19e91ef` measured the public host API on AMD EPYC 9V74.
Complete CPU/gas/memory/permissions/source snapshots and ordered host output pass, along with
all six refusal controls and the golden frame after 1,320 warmup ticks. Reused CPU medians in
forward/reverse process orders are initialization 441.529/443.947 ms versus PolkaVM interpreted
668.540/664.740 ms, and gameplay 55.215/54.919 ms versus 34.820/34.776 ms. The implementation
is unchanged between this measured cleanup head and its pre-cleanup integration parent. These
figures do not measure the later bounded-step change.

This confirms an integration gap: ordinary public calls reconstruct source facts, stream and
private memory. A local ARM64 same-binary diagnostic in both process orders measures public
planned sieve at 5.211/5.229 ms and public prepared-owner reuse at 3.853/3.830 ms. Those are local
diagnostic figures, not Linux measurements. Public prepared execution still constructs private
invocation memory and performs immutable publication; it must not be equated with core retained-
frame timing. The merge hold remains until public execution costs and Linux native qualification
are satisfactory. Next measurement must compare ordinary and prepared public APIs, retained core,
exact master and interpreted reference on the same runner, including cold and constructor costs.

## Same-runner public API measurement

The explicit Linux comparison now includes five roles on one runner: exact master with complete
pricing, ordinary current public API with complete pricing, current public PreparedProgram reuse,
retained-frame core, and pinned PolkaVM interpreted. A shared public driver image selects ordinary
or prepared ownership; fresh private-cache repeat builds still require byte-identical images.
The complete cohort has 60 measured processes / 780 calls, 100 positive/refusal controls and 12
repeat builds. Constructor, cold and reused samples remain separate. Both public modes construct
private invocation memory and publish inside their calls; retained core reset/publication remains
outside its call. Missing/duplicated public roles cannot publish an integrated timing table.

Public host-driver validation covers initialization and gameplay in both ownership modes, with
complete state/source/event checks and assertion, gas-state and event-refusal controls. The first
local probe altered a register while expecting a gas-specific diagnostic; its failure receipt is
retained, and the complete local cohort was rerun with the gas-field mutation corrected. All 71
selected parser/CI/host-tooling tests pass. These checks qualify the measurement harness, not a
new Linux performance claim; the full same-runner comparison must still complete.

## Codec deadline diagnostics

The later Linux Unit shard again exhausted the unchanged 180-second codec-batch deadline.
The adapter previously buffered an entire worker before emitting diagnostics, so that failure did
not identify an active suite. Codec workers now retain atomic active/completed receipts and exact
per-suite logs in their private cache's `codec-diagnostics` directory. Each attempt retires stale
receipts. Interrupted children retain active identities and never gain a fabricated completion;
ordered aggregate output and nonzero failure propagation remain unchanged. Unit artifacts retain
only these JSON/log files, not compiler objects. All 89 affected native-runner/CI safeguards pass.

A cold local reproduction of all 87 codec mains with fresh private caches and required independent
fixtures passes in 166.206 seconds under the original 180-second deadline. Completed work per
worker is 40.66/165.92/126.47/127.07 seconds. These are local whole-build/test scheduling figures,
not interpreter execution-speed measurements or a passing Linux receipt. The imbalance motivates
redistribution across the existing four workers before the next exact-head Linux request.

Codec mains are now assigned in strided source order across the same bounded serial workers.
Each worker still owns one private compiler cache and executes its assigned mains serially;
aggregate diagnostics are emitted in the original source order. Complete, unique result coverage
is checked before publication. A fresh-cache full 87-main local run passes in 136.200 seconds,
with worker totals 108.25/122.65/135.89/126.67 seconds, versus the 166.206-second contiguous run.
This is a local scheduling observation, not an engine speed claim. Both runs retain the same
sources, flags, independent fixtures and 180-second deadline. The 89 runner/CI safeguards pass;
Linux must still qualify the redistributed batch.

All 87 linked native images are byte-identical between the contiguous and strided worker runs;
redistribution changes scheduling, not the measured workload or build configuration.

## Empty invocation scratch

A genuinely empty guest map now omits the address-space dirty bitmap. No checked store can
succeed in that map; a host remap rebuilds the frame with its ordinary bitmap. Nonempty maps,
checked access, publication and cache policy are unchanged. A boundary witness enforces less
than 64 KiB of live frame scratch and checks the same one-step posterior state. It fails before
the change and passes afterward. The isolated checked local heap probe measures 135,168 bytes
before and zero additional live bytes afterward.

Six complete execution-cache witness runs per image, split across both process orders, retain
the original golden output and balanced 1,000-cycle ARC observation. Local ARM64 median process
CPU is 3.149 seconds before and 1.269 seconds afterward. This is an allocation-heavy single-step
witness, not a claim about Linux throughput or ordinary sieve/DOOM execution. Exact-head CI and
matched-toolchain performance qualification remain required.

## October 26 toolchain reconciliation

The native stack now descends from master `5bbe2a44b7b2cc4c6e0be58a1a8eebdb8abe1e32`,
including the October 26 Nimony upgrade to `358b9bce4dd855453f57a80a0c499b0b2e27d7ee`.
Historical scalar/prepared changes already landed as squash commits were reconciled against
their exact combined patch identities; distinct experiment commits remain intact. The old
decoder's heap-allocation adaptation is obsolete because integration removes that decoder.
The integrated engine, adapter, empty-map fix and comparison/scheduling tools remain byte-for-
byte unchanged from pre-restack commit `42937451`. The focused boundary suite and 94 affected
Python tooling/CI tests pass, and all 452 production modules plus the peer entry point pass
semantic compilation. Historical timing tables retain their original compiler provenance;
the upgraded compiler requires a new matched-toolchain Linux comparison before new claims.

All 19 calibrated native memory-check suites and their controls also pass on the upgraded
compiler. The six benchmark-driver pairs (master/core/public, kernels/DOOM) compile from fresh
private caches with byte-identical repeats: twelve successful builds. This verifies build and
measurement compatibility, not new Linux timing results.

## Qualified integrated Linux checkpoint, October 26 compiler

[Run 40470452175](https://github.com/jacogr/ragnarok/actions/runs/40470452175), artifact
`pvm-interpreter-linux-1`, completes the same-runner comparison on AMD EPYC 7763 with Clang 18.1.3,
ARC, checked release builds and ThinLTO. Both source heads use compiler
`358b9bce4dd855453f57a80a0c499b0b2e27d7ee`. Independent artifact verification confirms all
60 process identities / 780 calls, 100 positive/refusal controls, twelve fresh builds / six
byte-identical image pairs, six DOOM admission controls, 1,360 exact source hashes and 37
tracked input/helper hashes. Complete CPU/gas/memory/permissions/source snapshots and ordered
host events pass. The compiler's version banner was empty; the pinned manifest, captured Linux
compiler image hash and every build path agree. Binary/generated-input hashes are sealed runner
receipts; raw binaries are not in the artifact. These timings do not establish passing Unit CI.

Prepared-owner sieve calls are 17.7–18.6% faster than the interpreted reference, versus an ordinary
API deficit of 26.1–30.6%. Pinky and minimal are near reference speed. Prepared memory fill remains
63.1–68.1% slower, and DOOM gameplay remains 28.3–31.9% slower. The latter core call is near
reference (0.988–1.008x); its reset plus call plus immutable publication is 53.534–54.478 ms,
close to public prepared calls at 51.914–53.275 ms. This isolates a lifecycle cost worth investigating;
it does not prove a specific copy or allocation causes the gap. Next bounded experiment should
measure private invocation-memory construction and publication without changing checked access,
source budgets, host semantics or moving costs outside the accounting.

The table below preserves the measured head. Later changes to documentation or CI scheduling
do not create a new runtime timing receipt. No native instruction or hardware-counter data was
collected; the final table counts guest source attempts and resident prepared nodes.

Exact master: `5bbe2a44b7b2cc4c6e0be58a1a8eebdb8abe1e32`; candidate: `44ee182c23c52d8c9269ed2393da3db2d00c5ccc`.

CPU milliseconds. Both process orders; reused medians exclude the first three calls.
Master and ordinary public calls use complete pricing. Prepared API reuses source facts and stream,
but still creates private invocation memory and publishes an immutable result inside every call.

| Workload | Order | Master API | Ours ordinary API | Ours prepared API | PolkaVM | Ordinary / ref | Prepared / ref |
|---|---|---:|---:|---:|---:|---:|---:|
| pinky | 0 | 344.631 | 191.946 | 184.275 | 182.629 | 1.051 | 1.009 |
| pinky | 1 | 331.565 | 184.522 | 183.558 | 180.024 | 1.025 | 1.020 |
| sieve | 0 | 10.270 | 7.022 | 4.533 | 5.570 | 1.261 | 0.814 |
| sieve | 1 | 10.233 | 7.276 | 4.589 | 5.574 | 1.306 | 0.823 |
| minimal | 0 | 20.521 | 7.722 | 7.692 | 7.460 | 1.035 | 1.031 |
| minimal | 1 | 20.071 | 7.975 | 7.792 | 7.554 | 1.056 | 1.032 |
| memset | 0 | 10.735 | 7.340 | 6.853 | 4.202 | 1.747 | 1.631 |
| memset | 1 | 10.749 | 7.198 | 7.026 | 4.181 | 1.722 | 1.681 |
| init | 0 | 1869.558 | 605.140 | 589.646 | 770.554 | 0.785 | 0.765 |
| init | 1 | 1904.132 | 608.311 | 591.352 | 767.430 | 0.793 | 0.771 |
| tick | 0 | 119.343 | 68.199 | 53.275 | 40.378 | 1.689 | 1.319 |
| tick | 1 | 119.095 | 65.030 | 51.914 | 40.451 | 1.608 | 1.283 |

Retained-frame core is a separate scope: invocation reset and publication are outside its call.

| Workload | Order | Core call | Core reset + call + publication | Core / reference |
|---|---|---:|---:|---:|
| pinky | 0 | 185.223 | 185.474 | 1.014 |
| sieve | 0 | 3.713 | 3.780 | 0.667 |
| minimal | 0 | 7.636 | 7.644 | 1.024 |
| memset | 0 | 3.938 | 4.350 | 0.937 |
| init | 0 | 594.825 | 608.756 | 0.772 |
| tick | 0 | 40.710 | 54.478 | 1.008 |
| pinky | 1 | 184.526 | 184.756 | 1.025 |
| sieve | 1 | 3.783 | 3.851 | 0.679 |
| minimal | 1 | 7.634 | 7.642 | 1.011 |
| memset | 1 | 3.826 | 4.221 | 0.915 |
| init | 1 | 608.380 | 622.344 | 0.793 |
| tick | 1 | 39.982 | 53.534 | 0.988 |

Public API owner construction and cold first call (CPU ms). No reference-equivalent constructor claim.

| Workload | Order | API | Owner constructor | Cold call | Constructor + cold call |
|---|---|---|---:|---:|---:|
| pinky | 0 | master | 3.099 | 342.496 | 345.596 |
| pinky | 0 | public | 2.960 | 187.303 | 190.262 |
| pinky | 0 | prepared | 0.966 | 191.070 | 192.036 |
| sieve | 0 | master | 14.478 | 11.073 | 25.551 |
| sieve | 0 | public | 14.959 | 10.232 | 25.190 |
| sieve | 0 | prepared | 3.205 | 11.399 | 14.604 |
| minimal | 0 | master | 0.036 | 21.117 | 21.153 |
| minimal | 0 | public | 0.034 | 8.003 | 8.037 |
| minimal | 0 | prepared | 0.017 | 7.891 | 7.908 |
| memset | 0 | master | 0.256 | 10.783 | 11.039 |
| memset | 0 | public | 0.248 | 8.857 | 9.104 |
| memset | 0 | prepared | 0.068 | 10.122 | 10.190 |
| init | 0 | master | 47.267 | 1904.119 | 1951.386 |
| init | 0 | public | 46.789 | 610.041 | 656.830 |
| init | 0 | prepared | 10.972 | 603.085 | 614.057 |
| tick | 0 | master | 47.679 | 117.525 | 165.204 |
| tick | 0 | public | 46.405 | 68.756 | 115.162 |
| tick | 0 | prepared | 10.892 | 63.570 | 74.462 |
| pinky | 1 | prepared | 0.945 | 195.614 | 196.558 |
| pinky | 1 | public | 2.960 | 190.375 | 193.335 |
| pinky | 1 | master | 3.041 | 344.282 | 347.323 |
| sieve | 1 | prepared | 3.593 | 11.674 | 15.266 |
| sieve | 1 | public | 13.976 | 10.218 | 24.195 |
| sieve | 1 | master | 14.334 | 11.120 | 25.454 |
| minimal | 1 | prepared | 0.019 | 8.075 | 8.095 |
| minimal | 1 | public | 0.037 | 7.996 | 8.033 |
| minimal | 1 | master | 0.039 | 21.089 | 21.128 |
| memset | 1 | prepared | 0.071 | 9.478 | 9.549 |
| memset | 1 | public | 0.358 | 10.204 | 10.562 |
| memset | 1 | master | 0.253 | 10.761 | 11.014 |
| init | 1 | prepared | 10.784 | 603.342 | 614.125 |
| init | 1 | public | 46.410 | 615.663 | 662.073 |
| init | 1 | master | 47.458 | 1895.171 | 1942.629 |
| tick | 1 | prepared | 10.735 | 63.157 | 73.892 |
| tick | 1 | public | 46.373 | 72.930 | 119.302 |
| tick | 1 | master | 47.346 | 117.555 | 164.901 |

Constructors and first execution (CPU ms). Master calls include their immutable final publication;
ours publishes separately. PolkaVM has call-only timing; no equivalent constructor claim.

| Workload | Order | Ours plan / frame | Ours cold call | Ours cold lifecycle + constructors | Master cold call |
|---|---|---:|---:|---:|---:|
| pinky | 0 | 0.867 / 1.184 | 193.961 | 196.405 | 342.496 |
| sieve | 0 | 3.080 / 1.416 | 10.383 | 14.954 | 11.073 |
| minimal | 0 | 0.012 / 0.096 | 7.668 | 7.792 | 21.117 |
| memset | 0 | 0.069 / 4.870 | 4.118 | 9.383 | 10.783 |
| init | 0 | 11.774 / 17.017 | 604.110 | 648.860 | 1904.119 |
| tick | 0 | 11.934 / 17.185 | 45.925 | 91.225 | 117.525 |
| pinky | 1 | 1.161 / 1.122 | 188.313 | 191.080 | 344.282 |
| sieve | 1 | 3.414 / 0.964 | 9.478 | 13.932 | 11.120 |
| minimal | 1 | 0.016 / 0.125 | 8.009 | 8.170 | 21.089 |
| memset | 1 | 0.073 / 5.007 | 3.970 | 9.378 | 10.761 |
| init | 1 | 10.625 / 16.610 | 620.877 | 665.053 | 1895.171 |
| tick | 1 | 10.623 / 16.635 | 43.407 | 87.605 | 117.555 |

Fixtures, decoding and complete-state validation are outside these scopes. All samples,
master gas-plan constructors, image/source hashes and controls remain in results.json.
These are adapted checked workloads, not upstream stock benchmark scores. No hardware-counter claim.

| Workload | Order | Source attempts | Cold / reused nodes |
|---|---|---:|---:|
| pinky | 0 | 32055270 | 7852 / 7852 |
| sieve | 0 | 1166742 | 13938 / 13938 |
| minimal | 0 | 2000035 | 68 / 68 |
| memset | 0 | 1200349 | 487 / 487 |
| init | 0 | 203298231 | 36204 / 36204 |
| tick | 0 | 12180040 | 10759 / 10759 |
| pinky | 1 | 32055270 | 7852 / 7852 |
| sieve | 1 | 1166742 | 13938 / 13938 |
| minimal | 1 | 2000035 | 68 / 68 |
| memset | 1 | 1200349 | 487 / 487 |
| init | 1 | 203298231 | 36204 / 36204 |
| tick | 1 | 12180040 | 10759 / 10759 |

## Remaining Linux codec deadline and CI scheduling correction

Unit run `40470451184`, failed job `122076053110`, again reaches the unchanged 180-second
codec-directory deadline. Retained worker receipts identify 11/11/11/10 completed mains out of
22 per worker, with 178.66/157.41/178.25/162.15 seconds of completed work. The active mains are
`pvm_host_response`, `pvm_initialization`, `pvm_inner_invoke` and
`pvm_host_memory_reentry_reference`. This is balanced work that exceeds one Linux batch's
budget, not evidence of an individual interpreter hang. The unchanged local cold batch passes
all 88 mains in 133.306 seconds; local completion does not qualify that Linux deadline.

Multi-shard Unit plans now schedule each already-independent codec main as a normal source-owned
single-suite item across the existing runners. Unsharded local execution retains its directory
batch. Seeded dependency weighting, exact disjoint coverage, checked compiler/linker profiles,
fixture preparation, expected-output checks, ARC observations and per-command deadlines remain
enforced. No timeout or workload is weakened. A regression test caught an uneven legacy unseeded
stride during implementation; the balanced stride and full seeded/unseeded coverage checks now
pass. Fresh published-head Linux Unit qualification is still required, so the merge hold remains.

The correction passes 111 affected native-runner, cache, fixture, shard and CI safeguards.
All 88 redistributed mains retain exactly the directory build's checked compiler/linker flags.
The execution-cache suite passes its original 1,000-cycle ARC observation, and the complete-opcode
suite passes through the same single-main path used by the new CI plan. Production engine and
benchmark sources are unchanged from measured head `44ee182c`.
