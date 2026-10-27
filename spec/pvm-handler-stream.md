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
