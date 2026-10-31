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

## Fully overwritten resident byte storage

Invocation construction allocates `newSeqUninit[byte](pages*4096)` for each nonempty contiguous
run of equally permitted pages. It then copies the complete immutable source into that allocation
before adding the region to the private frame. This avoids zero-filling bytes immediately before
overwriting them. Fresh allocation, page-copy volume, admission limits and immutable snapshot
ownership retain their existing contracts; buffers are not retained between invocations.

The full-fill proof is local: `pages = after-first` is positive and bounded by `high(int) div 4096`.
Every page in `first..<after` writes exactly 4,096 bytes at `(page-first)*4096`, covering the
allocation without gaps or overlap. `copyMemoryPage` obtains all eight 512-byte chunks from the
same genuine immutable owner whose ordered metadata defined that run. No resident byte is read
before these copies finish. Inaccessible-only and empty layouts allocate no byte region. Regions
move into the frame and native descriptors are formed only after filling; a failed allocation or
assertion publishes no frame. Only byte arrays use the uninitialized allocator; typed metadata,
dirty bitmaps and protocol-required zero-filled memory keep their initialization contracts.

This uses the pinned Nimony 63fed6cb4 standard allocator (`seqimpl.nim`, `newSeqUninit`) and its
existing out-of-memory path, without a custom allocator or toolchain change. Scope follows the
approved Gray Paper `3861aed15d7d016a3a416e14e61fc67dddf6daec`, retaining PVM execution semantics.
Completion requires legal guest reads covering each initialized byte across primary and extra
RO/RW regions, adjacent pages, sparse gaps and the top address, plus existing host replacement,
reset, memory-pair and immutable-output checks. A private poison-allocation positive control and
missing-page-copy negative control check that source-copy omissions cannot be hidden by snapshot
reconstruction. All four affected Make suites (regions/host, memory pairs, host execution and
entry reuse),
three semantic backend configurations and source formatting pass locally. Poisoned allocation
passes; skipping page 38 fails the independent guest hash, while corrupting the top resident tail
preserves that hash and fails the dirty checkpoint comparison (165 versus 85).

Checked ARC/Clang ThinLTO comparisons against exact master `9e3cd38c` show a 21–25% lower
fresh-root execute component, but do not establish a full DOOM improvement: interpreted tick is
flat and JIT tick is 2.0–2.6% higher across two cohorts. Linked code confirms the baseline explicit
zero-fill is present and the candidate removes it inside the measured call. The standalone
master increment remains on performance hold. With the same harness and flags
after qualified source `74cdecf9`, three balanced ABBA cycles reproduce lower DOOM tick CPU:
26.015 to 24.999 ms interpreted (3.90%) and 19.391 to 18.339 ms JIT (5.43%). The three JIT pair
deltas are −4.43%/−4.61%/−5.55%; init is mixed and near parity. Fresh-root execute is 17.67%
lower. Driver/input bytes and backend receipts match, supporting an interaction with the two
preceding PVM changes without establishing its cause. This increment therefore follows that
qualified stack and requires its own Linux qualification against the exact parent source.
On the combined candidate, all 11 maintained local ARM native/refusal/ownership qualification
rows pass, including the direct read receipts and extended guest-byte/checkpoint witness.
Local receipts and the comparison cohorts are retained under ignored
`build/pvm-region-initialization/`.

### Resident allocation Linux verdict: preserved experiment

[ARM run 41231347423](https://github.com/jacogr/ragnarok/actions/runs/41231347423) passes correctness
at `98b1639e16f323a327003cd4d2b35e998366c4d8` against exact parent
`c83835e3cdf05c6800d973fd1a0a6ded29fb0555`. Raw parsing and source audit pass for 20 application
builds, 84 primary processes, 138 controls, 60 replays, 2,575 role-source identities and 519 native
identities, including all maintained native/refusal/ownership controls. Artifact 13054765316 ZIP
SHA-256 matches GitHub's digest:
`5e1cfb8c15b73180f5942cb0a6ab0a3e8aa05f018b8f6aa4097ecc0609249759`.
Application report SHA-256: `feded3c5429840750a3e4f262db82fa5db5271f8586c48a7aa64ed591da2e889`.

The Linux whole-application result does not reproduce the local gain. DOOM tick JIT primary CPU
is 27.156 to 27.403 ms and 27.477 to 27.045 ms (opposite directions); pooled replay medians are
27.240528 to 27.243766 ms, ratio 1.000119. Init JIT pooled ratio is 1.003108. Tick interpreted
primary ratios are 0.999826/0.985331; init interpreted is 1.011034/1.002976. Candidate tick ratios
to PolkaVM interpreted are 0.6847/0.6759 JIT and 0.7935/0.7967 interpreted within this cohort.
Long-sieve JIT is slower in all six replay pairs (pooled ratio 1.020192); short-sieve JIT is also
1.79%/1.84% higher in primary orders. These results do not justify a production merge.

The allocation code, byte-checkpoint witness and complete evidence remain preserved for reuse;
the proposal is closed and excluded from the active approved stack. No additional CI is needed
to repeat this verdict. The macOS improvement remains source/platform-specific evidence with no
established causal explanation.

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

Overlapping suffix emission preserves every existing complete entry-header mapping. Emitting an
earlier source entry may add operation nodes and update interior-only coordinates, but cannot
demote an already admitted entry to an interior coordinate. In particular, fresh calls through
one prepared owner at PCs `1, 0, 1` in `unlikely; unlikely; trap` reuse four nodes and eleven
preparation units without another admission. The `pvm_stream_entry_reuse` suite covers this exact
capacity and all six permutations of three entries at six nodes/fifteen preparation units, then
repeats every admitted entry with fresh immutable inputs. Literal trap/register/terminal-PC
expectations do not use another execution adapter as their oracle. This mapping fix does not
change suffix admission, sticky refusals, host continuation growth, gas or attempt accounting.

The defect was reproduced against unchanged master `51d6774f93365d0b76ab6bec738e532f7b5538b3`
in [CI run 40903185657](https://github.com/jacogr/ragnarok/actions/runs/40903185657): ARM64 and
x86-64, each with plain, matching-native-enabled and forced-native-refusal builds. The four-node
witness returned `InvalidPreparedProgram` on its third call while occupancy stayed four nodes
and eleven preparation units. These folded-noop/trap programs do not claim native opcode activity.

### Paid interior continuation

An actual execution entry with an already-paid block can reserve its remaining source suffix
directly through an existing interior body coordinate. It neither emits a second suffix/header
nor prices the paid block again. A partial reservation installs the same temporary budget barrier,
starting its search at the reused body; folded noops still stop at the exact original source PC.
Complete-header hits retain their normal dispatch. Unpaid, missing and invalid entries retain
their original admission/pricing/refusal order, and sticky preparation failures still win first.

This stateful reservation is confined to `runFlat`'s actual entry after its zero-attempt,
single-step, initialized-plan and sticky-refusal guards, with source-PC bounds checked before map access.
It is not part of `flatResolve`: static, conditional and indirect target preparation may run
while the old block is still paid, including prelinking an untaken branch arm. Those callers,
their paid-flag resets, ordinary `flatReserve`, memory workers and native generators are unchanged.
No owner, field, node representation, executable ABI or resource default is added or changed.

For `N` one-byte hosts followed by a trap, one initial admission occupies `N+2` nodes and
`2*(N+1)` preparation units; paid continuations reuse that occupancy. The former repeated-suffix
growth `(N+2)*(N+3)/2-1` refused a 4096-host block at PC 3955 under the unchanged default ceiling,
as independently reproduced in run 40903185657. The focused `pvm_stream_host_resume` suite checks
exact occupancy for dynamic/complete/lazy prices, prepaid zero-cycle inputs, zero/partial/exact
folded budgets, unchanged unpaid/sticky refusals, actual native prefix execution and partial
fallback where built, source-PC rejection, branch/dynamic prelink budgets and public prepared
callback/attempt limits with fresh immutable inputs. These are logical occupancy and correctness
witnesses, not timing or decoded-visit claims; complete independent state traces remain separate.
The existing resource-boundary host retry/mapping-replacement witness likewise keeps its initial
four preparation units and three nodes, rather than expecting seven units from re-emitting a paid
suffix. Its CPU, immutable page, permission/refusal and slow-replacement checks remain intact.

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

## Private invocation-region allocation trial

The corrected Unit run [40473624906](https://github.com/jacogr/ragnarok/actions/runs/40473624906)
passes completely at `665d6a9fb49e2070c9d29bd095a53a7027a6371c`. That is the accepted
prepared-parent source for the next bounded constructor trial, not a receipt for the trial itself.

An ignored source-copy diagnostic on Apple M1 Max isolates page-image extraction at about
0.75 ms and private region construction at 8.4–8.7 ms per DOOM call. Gameplay publication totals
about 0.4 ms per call. Instrumented clocks are diagnostic only. Production has no diagnostic hooks.
The trial scans each genuine contiguous permission run, proves its complete host allocation
extent, allocates that region once and copies each original page into its final offset. It retains
inaccessible snapshot metadata, arbitrary gaps, immutable source ownership, checked access,
whole-block pricing, source quotas, host transitions and publication. No allocation or validation
cost is moved outside the public call.

Baseline and candidate use fresh private compiler caches at identical canonical source/output
coordinates, pinned October 26 Nimony, ARC, Clang ThinLTO and checked release flags. Eight builds
produce four byte-identical repeat pairs. Both process orders cover all seven existing kernel
inputs plus DOOM initialization/gameplay: 54 measured processes / 702 checked calls and 87
positive/assertion/state/event controls. Full register/gas/page-byte/permission/source and ordered
host-event checks pass; every input and image identity remains stable through the cohort. An early
control harness expected a gas-specific diagnostic from the reference's aggregate state check;
that receipt is retained, the exact diagnostic is corrected and the complete cohort rerun.

These are local ARM64 CPU medians in milliseconds, forward/reverse process orders. They are not
Linux evidence. Prepared public calls include invocation memory and immutable publication; source
owner construction remains separate. Pinky's roughly 1% movement is below a useful timing claim.

| Workload | Accepted prepared parent | Exact-region trial | PolkaVM interpreted call | Trial / parent |
|---|---:|---:|---:|---:|
| sieve 1000 | 0.625 / 0.627 | 0.196 / 0.198 | 0.473 / 0.475 | 0.313 / 0.316 |
| sieve 100000 | 3.830 / 3.842 | 3.413 / 3.409 | 5.929 / 5.944 | 0.891 / 0.887 |
| minimal 1000 | 0.060 / 0.062 | 0.055 / 0.055 | 0.076 / 0.077 | 0.917 / 0.887 |
| minimal 100000 | 4.886 / 4.944 | 4.889 / 4.933 | 6.011 / 6.038 | 1.001 / 0.998 |
| memory fill 1000 | 2.345 / 2.352 | 0.765 / 0.673 | 0.132 / 0.134 | 0.326 / 0.286 |
| memory fill 100000 | 5.963 / 6.013 | 4.337 / 4.370 | 3.922 / 3.948 | 0.727 / 0.727 |
| pinky 1 | 84.763 / 84.433 | 85.400 / 85.282 | 94.022 / 94.703 | 1.008 / 1.010 |
| DOOM gameplay | 47.154 / 48.419 | 40.362 / 41.227 | 43.758 / 44.992 | 0.856 / 0.851 |
| DOOM initialization | 328.716 / 326.015 | 321.434 / 318.766 | 675.445 / 675.025 | 0.978 / 0.978 |

The trial is retained provisionally for matched-runner Linux qualification. The local gain is
about 14–15% for gameplay, 27% for the larger memory-fill case and 11% for the larger sieve case.
Minimal is effectively unchanged; the small initialization gain remains qualified by its scope
and spread. Remaining material platform regressions would require reconsidering this runtime trial.

## Reference lifecycle accounting

Earlier reference DOOM call clocks exclude instance construction/restoration; public prepared
calls include private invocation construction and immutable publication. Keep the old raw call
receipts, but do not describe those as equivalent invocation lifecycles. An explicit reference
measurement now separately accounts for private instance construction/restoration, execution and
teardown. Independent complete-state validation and fixture I/O remain outside. Reference module
construction and our prepared source-owner construction remain separate; immutable publication
has no reference-equivalent API operation. Default reference output and call-only timing stay
compatible, verified by a complete original-format thirteen-call run.

Strict lifecycle parsing requires all thirteen ordered call/phase pairs, exact positive durations
(with nonnegative teardown), matching call clocks, additive totals and the final state/event
success record. Partial, foreign, duplicated, inconsistent and overflowing records are refused.
On M1 Max, reference gameplay instance/restoration costs 2.155/2.099 ms and teardown about
0.004/0.005 ms. Total reference invocation lifecycle is 45.940/47.181 ms versus current prepared
public calls 40.362/41.227 ms. Both raw call and lifecycle ratios must remain visible.

Prepared public execution is the headline comparison. Ordinary entry points remain thin
compatibility adapters over this same engine; ordinary timing is diagnostic. An optional full
commit SHA adds an accepted prepared baseline alongside current master, current prepared public
execution, ordinary diagnostics, retained core and PolkaVM interpreted. That expanded cohort has
72 processes / 936 calls, 120 controls and sixteen fresh builds / eight equal-image pairs, plus
six shared DOOM admission controls. Invalid selectors fail before a SHA-only fetch; missing
baseline roles or reference lifecycle phases cannot publish a complete table.

Local qualification passes all 19 calibrated native memory suites and controls, the fragmented
regions/host witness, 452 production modules plus peer entry point, inventory and 75 affected
comparison/CI checks. Exact-head Linux parent pairing remains required before acceptance.

## Qualified Linux region-allocation verdict

[Comparison run 40483727387](https://github.com/jacogr/ragnarok/actions/runs/40483727387)
passes at measured candidate `e50f7413b7cecdca943cbbde0be43282f667a472`, paired with
accepted prepared parent `665d6a9fb49e2070c9d29bd095a53a7027a6371c` and resolved master
`5bbe2a44b7b2cc4c6e0be58a1a8eebdb8abe1e32` on one AMD EPYC 7763 runner.
All sides use October 26 Nimony `358b9bce4dd855453f57a80a0c499b0b2e27d7ee`.
The independent artifact verification reparses all 72 process transcripts / 936 checked calls,
120 positive/refusal controls, sixteen fresh builds / eight equal-image pairs and six shared
DOOM admission controls. It matches 1,814 exact committed source hashes and 38 tracked
helper/input hashes. Complete gas/register/page/permission/source snapshots and ordered host
events pass. Every reference DOOM process supplies thirteen exact call/lifecycle pairs with
matching call clocks and additive restoration/call/teardown totals. Raw executable images are
not downloaded artifacts: their hashes and fresh-cache equal-image checks are sealed runner
receipts. The compiler version banner is empty; pinned manifests, compiler image identity and
all build command paths agree. No hardware counters were collected.

**Keep the bounded allocation change.** Both process orders show useful parent-paired gains:
sieve 12.5–19.3%, large memory fill 25.2–27.3%, gameplay 5.5–8.6%. Pinky moves +1.2%/+0.2%,
minimal +2.1%/−0.9%, initialization −0.2%/+0.8%; these small or mixed differences do not support
material regression claims. The isolated production change remains final-size region allocation;
no memory checks, quotas, pricing, cache policy or host semantics changed.

Gameplay is still 18.8–25.6% above reference call-only timing and 7.4–13.7% above its measured
invocation lifecycle. The retained core is −3.4%/+2.4% versus reference call-only timing, while
reset/call/publication totals 45.512/47.507 ms. This supports investigating remaining invocation
construction/reset/publication overhead before changing the dispatch architecture; it does not
establish an exact additive decomposition across separate process samples. Preparation and cold
calls remain separate below. Ordinary calls are diagnostic compatibility wrappers over the same
engine; production callers retaining prepared owners remains separate caller-lifetime work.

Artifacts are retained locally under `build/pr-1724-region-linux/tests/pvm-interpreter-linux`,
including `independent-verification.json`, raw transcripts, controls and the complete result.
The following exact-head table supersedes provisional Linux qualification for this runtime trial;
previous runner/toolchain tables remain historical evidence. Documentation-only follow-up commits
do not change this measured-head provenance.

Exact master: `5bbe2a44b7b2cc4c6e0be58a1a8eebdb8abe1e32`; candidate: `e50f7413b7cecdca943cbbde0be43282f667a472`.

CPU milliseconds. Both process orders; reused medians exclude the first three calls.
Master and ordinary public calls use complete pricing. Prepared API reuses source facts and stream,
but still creates private invocation memory and publishes an immutable result inside every call.

| Workload | Order | Master API | Ours prepared API | PolkaVM | Prepared / ref | Ours ordinary API (diagnostic) | Ordinary / ref |
|---|---|---:|---:|---:|---:|---:|---:|
| pinky | 0 | 348.632 | 187.568 | 188.891 | 0.993 | 189.123 | 1.001 |
| pinky | 1 | 341.646 | 185.496 | 183.747 | 1.010 | 185.748 | 1.011 |
| sieve | 0 | 10.235 | 3.986 | 5.563 | 0.717 | 6.363 | 1.144 |
| sieve | 1 | 10.232 | 4.007 | 5.544 | 0.723 | 6.431 | 1.160 |
| minimal | 0 | 20.534 | 7.923 | 7.463 | 1.062 | 7.643 | 1.024 |
| minimal | 1 | 20.538 | 7.832 | 7.484 | 1.046 | 8.424 | 1.126 |
| memset | 0 | 10.740 | 5.044 | 4.177 | 1.208 | 5.073 | 1.215 |
| memset | 1 | 10.738 | 4.899 | 4.190 | 1.169 | 5.070 | 1.210 |
| init | 0 | 1912.556 | 591.124 | 776.309 | 0.761 | 606.637 | 0.781 |
| init | 1 | 1865.448 | 596.640 | 774.028 | 0.771 | 603.691 | 0.780 |
| tick | 0 | 119.192 | 48.108 | 40.484 | 1.188 | 62.542 | 1.545 |
| tick | 1 | 121.089 | 50.824 | 40.457 | 1.256 | 62.507 | 1.545 |

Prior prepared baseline: `665d6a9fb49e2070c9d29bd095a53a7027a6371c`.

| Workload | Order | Prior prepared API | Current prepared API | Current / prior |
|---|---|---:|---:|---:|
| pinky | 0 | 185.317 | 187.568 | 1.012 |
| pinky | 1 | 185.136 | 185.496 | 1.002 |
| sieve | 0 | 4.939 | 3.986 | 0.807 |
| sieve | 1 | 4.580 | 4.007 | 0.875 |
| minimal | 0 | 7.763 | 7.923 | 1.021 |
| minimal | 1 | 7.905 | 7.832 | 0.991 |
| memset | 0 | 6.745 | 5.044 | 0.748 |
| memset | 1 | 6.740 | 4.899 | 0.727 |
| init | 0 | 592.035 | 591.124 | 0.998 |
| init | 1 | 591.908 | 596.640 | 1.008 |
| tick | 0 | 52.663 | 48.108 | 0.914 |
| tick | 1 | 53.790 | 50.824 | 0.945 |

Retained-frame core is a separate scope: invocation reset and publication are outside its call.

| Workload | Order | Core call | Core reset + call + publication | Core / reference |
|---|---|---:|---:|---:|
| pinky | 0 | 189.294 | 189.517 | 1.002 |
| sieve | 0 | 4.078 | 4.140 | 0.733 |
| minimal | 0 | 8.208 | 8.216 | 1.100 |
| memset | 0 | 3.941 | 4.311 | 0.944 |
| init | 0 | 594.767 | 601.285 | 0.766 |
| tick | 0 | 39.127 | 45.512 | 0.966 |
| pinky | 1 | 190.598 | 190.809 | 1.037 |
| sieve | 1 | 4.104 | 4.178 | 0.740 |
| minimal | 1 | 7.998 | 8.006 | 1.069 |
| memset | 1 | 3.910 | 4.338 | 0.933 |
| init | 1 | 594.873 | 601.941 | 0.769 |
| tick | 1 | 41.438 | 47.507 | 1.024 |

DOOM invocation lifecycle: reference instance construction/restoration, call and teardown versus our prepared public call.
Reference module construction and independent full-state validation remain outside; ours includes immutable publication.

| Phase | Order | Reference instance + restore | Reference call | Reference teardown | Reference lifecycle | Ours prepared call | Ours / reference lifecycle |
|---|---|---:|---:|---:|---:|---:|---:|
| init | 0 | 4.117 | 776.309 | 0.156 | 780.774 | 591.124 | 0.757 |
| tick | 0 | 4.129 | 40.484 | 0.171 | 44.807 | 48.108 | 1.074 |
| init | 1 | 4.028 | 774.028 | 0.161 | 778.314 | 596.640 | 0.767 |
| tick | 1 | 4.057 | 40.457 | 0.153 | 44.692 | 50.824 | 1.137 |

Public API owner construction and cold first call (CPU ms). No reference-equivalent constructor claim.

| Workload | Order | API | Owner constructor | Cold call | Constructor + cold call |
|---|---|---|---:|---:|---:|
| pinky | 0 | master | 3.088 | 359.965 | 363.052 |
| pinky | 0 | public | 3.106 | 191.471 | 194.577 |
| pinky | 0 | baseline | 0.884 | 194.066 | 194.949 |
| pinky | 0 | prepared | 0.892 | 196.542 | 197.433 |
| sieve | 0 | master | 14.708 | 10.633 | 25.342 |
| sieve | 0 | public | 14.705 | 8.755 | 23.459 |
| sieve | 0 | baseline | 3.996 | 11.436 | 15.432 |
| sieve | 0 | prepared | 3.200 | 10.944 | 14.144 |
| minimal | 0 | master | 0.037 | 20.967 | 21.003 |
| minimal | 0 | public | 0.036 | 7.779 | 7.816 |
| minimal | 0 | baseline | 0.016 | 7.976 | 7.993 |
| minimal | 0 | prepared | 0.015 | 7.975 | 7.990 |
| memset | 0 | master | 0.252 | 10.845 | 11.096 |
| memset | 0 | public | 0.265 | 6.496 | 6.761 |
| memset | 0 | baseline | 0.070 | 10.112 | 10.182 |
| memset | 0 | prepared | 0.083 | 6.836 | 6.920 |
| init | 0 | master | 47.819 | 1916.765 | 1964.583 |
| init | 0 | public | 46.600 | 609.273 | 655.874 |
| init | 0 | baseline | 10.847 | 601.300 | 612.148 |
| init | 0 | prepared | 12.201 | 601.796 | 613.997 |
| tick | 0 | master | 47.396 | 117.232 | 164.627 |
| tick | 0 | public | 46.707 | 67.140 | 113.847 |
| tick | 0 | baseline | 10.830 | 60.006 | 70.836 |
| tick | 0 | prepared | 11.750 | 54.880 | 66.630 |
| pinky | 1 | prepared | 1.034 | 188.336 | 189.370 |
| pinky | 1 | baseline | 0.859 | 191.903 | 192.762 |
| pinky | 1 | public | 3.079 | 195.815 | 198.894 |
| pinky | 1 | master | 3.035 | 340.563 | 343.599 |
| sieve | 1 | prepared | 3.663 | 10.999 | 14.661 |
| sieve | 1 | baseline | 3.180 | 11.427 | 14.607 |
| sieve | 1 | public | 14.626 | 8.818 | 23.445 |
| sieve | 1 | master | 14.493 | 11.048 | 25.541 |
| minimal | 1 | prepared | 0.023 | 7.816 | 7.839 |
| minimal | 1 | baseline | 0.024 | 8.148 | 8.172 |
| minimal | 1 | public | 0.047 | 8.329 | 8.376 |
| minimal | 1 | master | 0.046 | 21.397 | 21.443 |
| memset | 1 | prepared | 0.085 | 8.283 | 8.368 |
| memset | 1 | baseline | 0.084 | 9.952 | 10.037 |
| memset | 1 | public | 0.266 | 6.676 | 6.942 |
| memset | 1 | master | 0.252 | 10.761 | 11.014 |
| init | 1 | prepared | 10.854 | 604.289 | 615.144 |
| init | 1 | baseline | 10.723 | 609.399 | 620.122 |
| init | 1 | public | 46.804 | 609.997 | 656.800 |
| init | 1 | master | 47.308 | 1868.706 | 1916.014 |
| tick | 1 | prepared | 12.026 | 58.130 | 70.156 |
| tick | 1 | baseline | 10.769 | 60.082 | 70.851 |
| tick | 1 | public | 46.766 | 66.064 | 112.830 |
| tick | 1 | master | 47.818 | 118.685 | 166.503 |

Constructors and first execution (CPU ms). Master calls include their immutable final publication;
ours publishes separately. PolkaVM has call-only timing; no equivalent constructor claim.

| Workload | Order | Ours plan / frame | Ours cold call | Ours cold lifecycle + constructors | Master cold call |
|---|---|---:|---:|---:|---:|
| pinky | 0 | 1.003 / 0.501 | 195.431 | 197.529 | 359.965 |
| sieve | 0 | 3.148 / 0.361 | 9.719 | 13.300 | 10.633 |
| minimal | 0 | 0.010 / 0.095 | 8.101 | 8.224 | 20.967 |
| memset | 0 | 0.067 / 1.728 | 4.130 | 6.301 | 10.845 |
| init | 0 | 10.703 / 6.945 | 605.721 | 631.030 | 1916.765 |
| tick | 0 | 12.011 / 6.948 | 44.814 | 72.556 | 117.232 |
| pinky | 1 | 1.005 / 0.549 | 194.151 | 196.273 | 340.563 |
| sieve | 1 | 3.290 / 0.680 | 9.664 | 13.716 | 11.048 |
| minimal | 1 | 0.013 / 0.097 | 8.276 | 8.407 | 21.397 |
| memset | 1 | 0.069 / 1.623 | 4.096 | 6.147 | 10.761 |
| init | 1 | 10.698 / 6.796 | 604.694 | 630.011 | 1868.706 |
| tick | 1 | 10.843 / 7.019 | 45.830 | 71.228 | 118.685 |

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

### Merge readiness after the allocation trial

The performance gate for retaining this trial passes. Current exact-head Unit run
[40484013910](https://github.com/jacogr/ragnarok/actions/runs/40484013910) remains in progress
without a reported failure at recording time. Its pending state does not establish complete
Linux qualification, so the merge hold remains. Parent Unit run 40473624906 passed completely;
its result does not substitute for the candidate run. No merge is performed. Remaining gameplay
cost and unused private single-mode forwarding are explicitly separate follow-up work.


## Regular comparison scheduling

`Perf / PVM Comparison` runs on master pushes, manual `perf`/`full`/`bench-pvm` requests and
open PR requests through `ci:perf` or `ci:full`. Ordinary PR updates retain their light smoke
selection. The Perf aggregate requires both its existing families and this same-runner comparison
to succeed. The comparison retains exact-master/source evidence, checked public and core scopes,
DOOM lifecycle observations, summaries and refusal artifacts; its command and timing boundaries
are unchanged. The broader name leaves room for later backend coverage.


### Post-merge comparison harness correction

Master run [40505388921](https://github.com/jacogr/ragnarok/actions/runs/40505388921)
at `2f0bcae018eca7f31fa7ee576ac0472ee36debef` exposed two harness regressions.
Reference & Tooling failed on three stale workflow expectations after the comparison job rename
and Perf dependency expansion. The comparison failed compiling its master DOOM driver: historical
constructor-clock source injection broke indentation after the driver's preparation became conditional.
The aggregate Compile and Perf failures were consequences of these originating jobs.

The comparison now compiles the exact committed public driver with only its existing import-path
relocation. Master DOOM enables and strictly parses the driver's existing `API_PREPARE,planned`
constructor record, matching the ordinary public role. Call boundaries, complete state/host-event
checks, source seals, repeated fresh builds and refusal controls remain mandatory. Tests cover
all sixteen Perf dependency result combinations and reject missing or historical constructor output.
Local verification includes all CI/comparison safeguard tests, related parsers, verification inventory
and real master DOOM initialization/gameplay calls with assertion refusals. Linux confirmation is
separate from these local checks; this correction changes no production interpreter source.


## Deferred complete-reservation endpoints

The checked interpreter and native whole-block entries still deduct the original source quota
at exactly the same point. A complete reservation now retains its stable stream-header offset
instead of reading the source-index array to calculate an endpoint on every entry. Only an
attempted terminal, fault or host exit resolves that header to `sites[header] + arguments[header].y`
before refunding the unexecuted source suffix. Gas refusals and local errors retain their original
ordering and do not create an attempted exit.

The private 32-bit reservation word distinguishes a raw source end from a header using bit31.
Source ordinals are bounded by the existing four-MiB source limit, and emitted offsets remain
below 2^31 under node admission. Partial quotas and paid interior resumes keep their exact raw
source end because it also identifies the temporary source-budget barrier. Native region state
retains the last completed header. The four-iteration checked word loop identifies its original
five-source-instruction header. No CPU state, source quota or executable owner is added to the
reusable stream.

Header arguments and source coordinates remain unchanged during a reservation, and the exclusive
stream lease survives through exit accounting. Temporary budget handlers are restored before
publication. The endpoint is resolved before host observation, stream transfer or frame retirement;
immutable snapshots, host response validation and native cleanup retain their existing contracts.

Scope follows the approved Gray Paper source pin `3861aed15d7d016a3a416e14e61fc67dddf6daec`,
which retains the existing PVM rules and source-attempt interpretation from
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`. Guest gas, instruction effects, exit PC, mapping
permissions, local resource admission and fallback retain their established contracts.

### Deferred reservation qualification

[Linux ARM run 41221760201](https://github.com/jacogr/ragnarok/actions/runs/41221760201)
qualified combined stack `74cdecf940b3cc8e1772b4164edd25283a07ed4f` against exact baseline
`f8612e62105d1a4b446d320f87df83eafeb95819`, including the companion guarded direct-read/branch
fragment. These are combined-stack native results; they do not isolate each layer's native gain.
The current master source refresh 9e3cd38c changes the approved credential-source pin and retains
identical PVM/native/toolchain inputs to the baseline.

The cohort used Nimony 63fed6cb4, checked release/ARC/Clang 21.1.8 ThinLTO on one Linux ARM runner.
All 20 fresh builds, 84 primary measured processes, 138 positive/refusal controls and 60 native replay
processes passed. Re-parsing every record, matching 2,575 role source identities and 519 native
source identities, and checking the equal-policy executable images passed. Native/direct-read,
word-loop, owner transfer and storage-refusal witnesses also passed. The artifact 13049874501 ZIP
SHA-256 is `ee6ef3c0815a2e31d80b2b9cec6aaa3fa298afb396175c98b639c5c06b223f51`.
The application report SHA-256 is `663f67d6d1e2118416b503bb41c26d48c3305995dce4159a159447e26bdd4d26`.

CPU milliseconds are ten-sample medians after three warmups in each process order. Ratios use
PolkaVM interpreted calls from the same runner and order; lower is better.

| Phase/order | Baseline interpreted | Stack interpreted | Interpreted/PolkaVM | Baseline JIT | Stack JIT | JIT/PolkaVM |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0 | 435.987 | 407.464 | 0.6527 | 231.654 | 237.091 | 0.3798 |
| init/1 | 435.582 | 410.104 | 0.6532 | 237.109 | 229.508 | 0.3656 |
| tick/0 | 33.596 | 32.707 | 0.8152 | 29.308 | 27.968 | 0.6971 |
| tick/1 | 33.475 | 32.414 | 0.8083 | 29.436 | 28.006 | 0.6984 |

Interpreter init CPU is 5.8–6.5% lower and tick 2.6–3.2% lower. JIT tick is 4.6–4.9% lower in the
primary orders; all six independent replay pairs improve, with pooled median ratio 0.952657.
JIT init primary orders change direction (+2.35%/−3.21%); five of six replays improve and the
pooled median ratio is 0.985999. This does not establish a uniform init gain.

The control tradeoff remains explicit: long-sieve JIT CPU is1.27%/2.45% higher in the primary
orders and all six replay pairs are higher (pooled ratio 1.014875). Its hot branch/header counts
are identical, and the lowered-operation difference is only 22 in 1.29 billion; these counters do
not identify a cause. A private 64-byte fragment-alignment trial had no established local gain
and was not adopted. Short-sieve JIT primary ratios are 1.0008/1.0092; minimal, Pinky and memset
JIT improve in both orders, while interpreted controls improve. No across-the-board speed claim
is made. DOOM call CPU includes fresh invocation memory and in-memory callbacks; preparation,
file I/O and final reference validation remain outside that call scope.

Local supporting checks passed all three backend semantic configurations and six affected Make
suites: accounting, checked word loops, host resume, stable entry reuse, mixed independent
reference and host-memory reentry reference. The 18,432-case accounting suite passes the real
implementation and rejects a missing header-span mutation at the expected Host quota mismatch.
Combined native qualification, all-opcode/region-host suites and source formatting passed.
Linked ARM code removes five reservation-metadata instructions from the ordinary whole-block
success path; exit accounting retains the source bounds checks where the end is used.


### Deferred reservation x86 qualification

[Linux x86 run 41227642672](https://github.com/jacogr/ragnarok/actions/runs/41227642672) passed at
that same source head `74cdecf940b3cc8e1772b4164edd25283a07ed4f` against `f8612e62105d1a4b446d320f87df83eafeb95819`.
The AMD EPYC 7763 runner used the same pinned compiler/checks/ARC/ThinLTO policy. All 20 builds,
84 primary processes, 138 controls, 60 replay processes and 15 native qualification groups pass.
Independent raw-output parsing and comparison of 2,575 application-role source identities and
497 native project-source identities pass, including real executable storage, native/refused
arithmetic and branch matrices, region contexts, source boundaries and arena/stream/frame ownership.
The artifact 13053510309 ZIP SHA-256 is
`f5f11ac27ac0e2d475129566383fd4b96d578b8190d60aac17553d67f186c16f`; application report SHA-256 is
`63576570a6e96b42e9e51682d50a4954d1c4f9c5cf8f9afc2ac76211dbcb27b6`.

The ARM-only read/branch lowering is inactive in this build. CPU milliseconds and same-order
ratios to PolkaVM interpreted follow the ARM table's collection protocol.

| Phase/order | Baseline interpreted | Stack interpreted | Interpreted/PolkaVM | Baseline JIT | Stack JIT | JIT/PolkaVM |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| init/0 | 519.051 | 532.199 | 0.6287 | 533.891 | 544.835 | 0.6436 |
| init/1 | 523.003 | 504.923 | 0.5972 | 550.155 | 514.211 | 0.6081 |
| tick/0 | 41.160 | 39.553 | 0.6957 | 55.868 | 51.132 | 0.8994 |
| tick/1 | 40.766 | 38.512 | 0.6753 | 56.569 | 51.183 | 0.8975 |

DOOM tick interpreted CPU improves 3.9–5.5% and JIT improves 8.5–9.5% in primary orders.
All six tick JIT replay pairs improve, with pooled median ratio 0.949752. Initialization changes
direction in primary orders for both engines; all six JIT initialization replays improve, pooled
ratio 0.976083. Long-sieve JIT replays improve, pooled ratio 0.935137. Some controls remain mixed:
interpreted Pinky is 1.24%/10.05% slower, and minimal/memset comparisons change direction.
The x86 JIT still costs 29–33% more tick CPU than this stack's interpreter on the same runner;
reducing native transitions remains future architecture work. The ARM long-sieve tradeoff remains
as recorded above. These outcomes do not establish uniform gains across applications or machines.
