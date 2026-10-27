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
