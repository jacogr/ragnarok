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

The same CI define retains private per-source classification bytes and exposes a copied test-only
lookup. It verifies a specific entry before/after native map saturation without rescanning or
constructing anything after sealing. Repeated leases and host mapping replacement retain this
observation; ordinary production owners contain neither the table nor its lookup API.

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
alone is insufficient evidence of eligible native source. ARM uses a static no-publication
specialization of the same arithmetic/read/span compiler, including emitted-word size and original
short-prefix fallback; it never substitutes an opcode/count heuristic for the real read admission
policy. The specialization allocates only bounded transient words and neither consults/mutates a
native entry map nor creates/publishes an arena. The pure x86 bounded floor retains its existing
span/header policy. These checks distinguish unsupported/short/all-noop entries from map-capacity
deferral. Explicit byte/slot
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
and performance run on CI. The functional receipt and unresolved cost gate below supersede the
initial pending status; source checks alone do not establish runtime correctness or performance. Public
Compiled integration, real continuing CLI eager cohorts and PolkaVM compiled comparisons remain
dependent work owned separately. This prerequisite does not close issue #1733.

## October 29 functional qualification and cost hold

The measured candidate is `740d2571d92e07ea0fa9a579133c5a1bd99dd442`, based on repaired master
`8d398689db55031809445fc1db30de5ac9f6c328`. Its separate changes include the real ARM admission
policy fix in `2208c092083e1202df34b19e270a6a17bfcc06c3` and preservation of the original frame
field coordinates in `85b16fdce5753acb8fcd0c535b85551b6a80596d`. The latter keeps eager state
after all original fields, but still enlarges the frame; no CPU cause is inferred from that layout.

[ARM run40840803110](https://github.com/jacogr/ragnarok/actions/runs/40840803110) and
[x86 run40840806645](https://github.com/jacogr/ragnarok/actions/runs/40840806645) pass the complete
native qualification and matched comparison protocols. Each architecture independently retains
70 measured processes /910 complete-state calls,115 controls,16 fresh builds/eight equal-image
pairs, plus60 fresh-process replications. The compiler is the unchanged October28 pin. The x86
receipt identifies AMD EPYC9V45; the ARM receipt reports native aarch64. Figures are paired only
within each runner. Receipt SHA256 values are:

- ARM: `979c85b72d267e66ed6f84983483a9e1fa1fe3fafd0051d394474358e222a4d1`.
- x86: `ed1475e34e74d2ae10a17d8fcedba171f90464d482e38a3264a759f816c5ce9e`.

Internal sealing witnesses pass three fresh processes of the same image, including successful
native construction before any native calls, advancing calls/operations with frozen construction
observations, refused storage, complete interior-PC/prefix/paid/gas coverage and exact source
identity. ARM's reviewed counterexample is now explicit: the first entry of33 or64 consecutive
opcode124 reads is checked both at ordinary coordinates and after132000 trap blocks exceed the
native map. The32-read neighbor is a real native entry at ordinary coordinates and capacity-deferred
beyond that map. This uses the same no-publication builder and preserves all original size limits.

The later `9f652e2cd86b794904b7e8e25ae8a260556c7db2` changes only indentation of one comment.
Its runtime tokens are unchanged (`git diff --ignore-all-space` is empty). Fresh ARM, Linux-x86,
unbuilt and refused source profiles pass on that formatted tree, and
[smoke40841498015](https://github.com/jacogr/ragnarok/actions/runs/40841498015) passes. Native
and CPU evidence remains attributed to740d; it is not relabeled as a new measurement of9f.

Current public reused CPU milliseconds, forward / reverse. Constructor, cold, retained core,
reset/publication and reference restore/teardown remain separate in the retained reports.

| Workload | ARM baseline | ARM candidate | x86 baseline | x86 candidate |
| --- | ---: | ---: | ---: | ---: |
| sieve100k | 2.951 /2.962 | 2.928 /2.956 | 1.697 /1.614 | 1.697 /1.638 |
| minimal | 5.443 /5.483 | 5.549 /5.716 | 3.590 /3.541 | 3.657 /3.431 |
| fill | 4.387 /4.388 | 4.363 /4.407 | 2.709 /3.986 | 2.719 /2.494 |
| Pinky | 85.276 /84.998 | 84.767 /84.728 | 65.152 /63.262 | 64.974 /62.671 |
| sieve10m | 282.652 /281.963 | 289.595 /289.783 | 165.476 /162.906 | 163.118 /164.976 |
| DOOM initialization | 314.624 /326.668 | 328.867 /324.297 | 287.283 /287.195 | 291.307 /291.329 |
| DOOM gameplay | 41.240 /41.272 | 41.294 /41.524 | 31.597 /29.212 | 31.361 /32.647 |

Verdict: functional interface qualified, performance keep/merge blocked. ARM long-sieve is about
2.46/2.77% slower in the main pairs. Six fresh-process medians independently give282.015ms baseline
versus289.445ms candidate (+2.63%); ranges280.902–282.640 and284.233–290.286 do not overlap.
ARM gameplay replication40.952→41.014ms is close; its minimal5.524→5.601ms is about1.4% slower.
x86's main pairs have visible order variation; replication medians are minimal3.428→3.338ms,
long-sieve165.172→167.141ms, initialization278.302→283.896ms and gameplay30.585→30.903ms with
overlapping ranges. No blanket improvement or hardware-cause claim follows. No paired baseline
retained-core number is manufactured, and these replay runs did not collect instruction/call-arc
profiles. The repeated ARM regression remains a real default-JIT cost gate.

Historical failures remain preserved. Initial `20cd1530828b14cf6681d48fbccbb989323f6396`
[ARM40835730400](https://github.com/jacogr/ragnarok/actions/runs/40835730400) failed a new linked
sealing assertion with no expression printed; legacy native/refusal/all-opcode/host suites had
passed and no benchmark ran. Later diagnostic heads add named conditions, deterministic inputs,
safe copied observations and explicit default-result initialization. The assertion has not
reproduced; no root cause is assigned from subsequent passing runs. The separate earlier
`d45edec3b381637f282311242398f1b6d2e5aa51` ARM40836891168/x8640836895047 cohorts pass their
protocols but retain material long-sieve and x86-minimal regressions. They are historical non-keeps.

Review has cleared the functional shared interface for private public-policy integration while
the performance gate remains open. The next bounded decision is matched profiling of the actual
candidate against its baseline, or moving eager state into the existing exclusive native owner
to restore original frame size as well as coordinates. That extraction requires a coordinated
scope decision; no cache/region-cap increase, opcode work or unchecked path is justified by these
numbers. Public eager selection, continuing eager CLI parity and compiled-reference comparisons
remain separate dependent qualification.
