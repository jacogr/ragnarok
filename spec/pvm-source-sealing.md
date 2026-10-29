# Shared source-only PVM preparation

Refs #1733. This prerequisite supplies eager construction of the existing independent handler
and native generator. It does not claim complete native opcode coverage or a comparison against
PolkaVM compiled. Public `Compiled` policy/CLI integration is a separate dependent change.

## Authority and interface

The pinned Gray Paper and existing program, gas, execution, handler-stream, native-cache identity
and host contracts remain authoritative. The October 28 Nimony revision remains
`63fed6cb4b2f59d34c9fbb18f1796e671e2024e4`. No pins, source prices, arena sizes, publication limits,
observed-edge policy or public JIT selection change.

`prepareFlatStream(plan: FlatPlan): FlatResult[FlatStream]` accepts an already admitted complete
source plan as its only authority. It accepts no Machine, memory, registers, invocation descriptors,
callbacks, guest gas, source-attempt budget, or duplicate FlatLimits. Construction never runs a
guest instruction or calls a native leaf. A temporary private construction frame contains only
source/stream/compiler ownership; its guest regions are empty and unused.

The result is transactional and exclusive. A failed/default result carries only a typed reason;
partial arrays/native owners retire through the existing ARC/arena ownership contracts. A successful
owner transfers through `takeFlatStream` / `restoreFlatStream`, including host mapping replacement.
Its exact admitted FlatPlan binds even a zero-native owner. Refused restore consumes no source
stream. Separately admitted equal bytes do not authorize code reuse.

Errors append to FlatError without changing existing ordinals:

| Error | Meaning |
| --- | --- |
| NativeNotBuilt | Neither generator was built. |
| NativePlatformUnsupported | Selected generator does not support this OS/CPU. |
| NativeStorageUnavailable | A real executable arena owner could not be created, including all-fallback source. |
| InvalidPolicy | Plan is not a complete native-enabled execution plan. |
| StreamLimitExceeded | Complete shared nodes plus all entry headers exceed the plan's node allowance. |
| PreparationLimitExceeded | Complete construction exceeds the plan's preparation allowance. |

Ordinary plan admission retains its existing typed source/fact/jump/policy errors. Native map,
publication-slot and code-byte exhaustion preserve a complete checked stream and reported fallback;
they do not masquerade as structural construction success with missing nodes. Process-wide allocator
failure follows the pinned runtime's allocation contract; this hook does not invent recoverable
out-of-memory exceptions or change allocator policy.

## Linear complete entry domain

Construct block bodies once in ascending source-PC order through the existing resolver/generator.
Every genuine instruction PC then receives a charge header pointing to the corresponding shared
body coordinate. Headers for interior PCs are appended outside sequential operation bodies. Folded
noops point at the next real operation within their own block; their original source attempts and
partial-budget PCs remain explicit. No header points at another newly appended header.

For N genuine instructions, B blocks and R non-noop operations, final logical nodes are N+R and
reserved preparation units are 2N+(N-B). The 2N reserves existing body emission plus containing-block
pricing once; N-B reserves each additional interior entry header once. These units are bounded
source-work reservations, not CPU instructions or measured decoder visits. Node/work preflight
occurs before executable storage allocation. Native scans retain their existing fixed 64-operation
bound, so construction and coordinate-capacity classification are linear with a fixed factor.

Shared body workers remain valid at every interior start: original second members of fused pairs
remain addressable, adjacent pairing never consumes an earlier instruction, and the active body's
temporary source barrier preserves folded-noop and memory-pair partial prefixes. Dynamic targets
still require the original jump-table and block-membership capability. Invalid PCs/targets retain
the existing checked error/panic path; no missing map entry grows a sealed owner.

## Pricing and frozen execution

One private direct price/error fact per containing block is computed during body construction.
Its error is observed only on an attempted unpaid entry. `flatSealedCharge` uses that fact for
direct pricing or consults the invocation's selected GasPlan/GasMemo at that same entry boundary.
Zero attempts and already-paid entries never query external pricing. Untaken blocks cannot add
caller-visible GasMemo entries, consume guest gas, change paid state, or raise a guest pricing error.

The eager constructor replaces every native pending-promotion worker with its already published
leaf worker. Its dedicated charge headers cannot select charged-shape cold preparation or whole-block
region probes. No observed connected edge is collected for eager code. Existing JIT construction
and lazy handler selection continue through their existing paths.

The sealed-path audit covers these admission sites:

- `flatResolve` and `flatEmit`: all valid PCs already have headers; sealed misses refuse; emission asserts unsealed state.
- `flatArmPrepare` / `flatX86Prepare`: refuse a sealed construction pass before scanning.
- `flatArmUpgrade` / `flatX86Upgrade`: sealed guard and construction-selected leaf workers prevent late control publication.
- ARM read/span builders: reachable only through cold ARM preparation, with no invocation descriptor used during emission.
- ARM/x86 cycle publication: sealed guard; eager construction installs no probing/connected handler.
- charged-shape cold workers: all eager primary headers become dedicated checked charge entries.
- static/dynamic target linking and register/branch handler specialization: may change bounded existing scalar links/workers, without new nodes, code, preparation or publication.

Native memory code receives current invocation descriptors at each call. Eager emission neither
reads nor retains them. Mapping repair rebuilds those descriptors while preserving exact-plan code.
Code bytes, successful publications, preparation units, logical nodes and source classifications
freeze. Calls, lowered operations, branch/header execution and host counters remain live.

`pvmSourceSealingReceipt` adds CI-only attempted native compiler/admission-pass instrumentation,
including refused upgrade/cycle/span scans. All internal native entry points increment it before
their guard. It freezes with the test snapshot across execution and mapping repair; production
builds omit this instrumentation and its field. Thus a coarse zero compilation-clock delta alone
cannot satisfy the no-later-compilation witness.

## Copied diagnostics and counting units

`streamSealedInfo(stream)` returns copied `FlatSealedInfo` with a sealed flag and these source-entry
PC counts:

| Field | Unit and classification |
| --- | --- |
| candidates | Every genuine instruction PC, exactly once. |
| nativeEntries | Source PCs whose shared body starts at an actually published native entry. This is not all instructions covered by native fragments. Folded prefixes may share that entry. |
| checkedEntries | Canonical checked entry under the current lowering/span/entry policy. |
| capacityDeferred | Otherwise eligible entry refused by finite native coordinate, publication or byte capacity. |

The three outcomes are mutually exclusive and sum to candidates. A missing native coordinate map
alone is insufficient evidence of eligible native source: a bounded source eligibility check
distinguishes unsupported/short/all-noop entries from map-capacity deferral. Explicit byte/slot
refusals use an existing non-executable entry marker with a cold diagnostic sentinel. It never
becomes a callable code offset or replaces an already published native entry.

Existing `streamNodes`, `streamPreparation` and `streamNativeStatistics` expose separate copied
observations. Native statistics remain `[fragments, calls, operations, codeBytes, compilationNs,
branchCalls, headerCalls]`. Fragments count cumulative successful physical publications, including
successful replacements, not active occupancy or source-entry coverage. Source/cache leasing and
host mapping repair never reset that counter. ARM retains its reserved region publication slot;
eager preparation does not consume it by inventing a connected region. Capacity constants remain
unchanged on both architectures. No mutable arrays, code mapping or allocator pointers escape.

## Verification and limits

`test_pvm_source_sealing` is an ordinary discovered source suite and is also selected with the
matching native define and `pvmSourceSealingReceipt` by both existing native CI qualification
drivers. Its refused twin requires the exact storage refusal. The no-generator ordinary suite
requires NativeNotBuilt. Positive native tests require construction publications/bytes with zero
calls/operations, followed by advancing native execution and unchanged frozen observations.

Witnesses cover every genuine entry and source prefix under paid/unpaid and gas-edge states,
all valid opcodes with bounded deterministic operands, folded noops and fused pair interiors,
dynamic/static targets, memory aliases/permissions, host continuation/remapping, source identity,
direct/plan/memo pricing, cycle-price refusal, linear node/work boundaries and independent native
map/slot/byte/storage refusals. Full registers, PC, gas/deficit, paid flag, source-attempt balance,
exit/fault/host values, immutable source and mapped bytes/permissions are checked against forced
independent interpretation.

Local verification is source/semantic/Python/format only. Native construction, linked execution
and performance run on CI. Exact-head two-architecture JIT regression qualification and results
remain pending; source checks alone do not establish runtime correctness or performance. Public
Compiled integration, real continuing CLI eager cohorts and PolkaVM compiled comparisons remain
dependent work owned separately. This prerequisite does not close issue #1733.
