# Gray Paper discrepancies and ambiguities

The Gray Paper is the primary specification. Ragnarök implements it independently;
pinned PolkaVM is an implementation cross-check for PVM fixture compatibility.
An accepted local behavior does not resolve a specification question upstream.
This register records findings encountered during implementation, not an exhaustive
paper audit. Entries below have not been filed upstream by this work; no claim is
made about whether a later paper revision already fixes them.

## Baseline and reporting policy

Reviewed on2026-10-21 against Gray Paper0.8.0
`07f041dabd073f9018b418e9ee72e79dd2185401`, PolkaVM0.37.0
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`, and reference vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.
Source digests are recorded in [protocol pins](pins.json) and
[PolkaVM pins](polkavm-pins.json). Links below identify immutable source revisions.

Each finding keeps a stable ID, classification, minimal input, competing results,
source evidence, local disposition and fixture coverage. Distinguish source-derived
reference behavior from executed upstream tests. Before filing, check the then-current
paper and existing issues; preserve this pinned finding even if a later revision fixes it.
Attach the minimal witness and ask for a normative rule, rather than presenting our
chosen compatibility behavior as proof that the paper must change.

| ID | Classification | Finding | Local status |
| --- | --- | --- | --- |
| GP-PVM-001 | Internal ambiguity | Wrapping access: protected-low-memory prose versus minimum-index fault equation | Scoped compatibility rule tested; upstream clarification needed |
| GP-PVM-002 | Paper/implementation discrepancy | Mapped final byte is accessible in the paper but traps in PolkaVM | Explicit compatibility exception tested; upstream clarification needed |
| GP-PVM-003 | Missing definition | Branch gas lookup at a negative mathematical target | Wrapped-target price tested; upstream clarification needed |
| GP-PVM-004 | Paper/implementation discrepancy | Final fallthrough/conditional: runtime panic versus module rejection | JAM preparation matches PolkaVM; raw paper witness retained |
| GP-PVM-005 | Paper/implementation discrepancy | Jump-entry widths above4 accepted by paper, rejected by PolkaVM | JAM rejection tested; open PR559 proposes the bound |
| GP-PVM-006 | Paper/implementation discrepancy | Nonempty width0 table versus semantically empty table | JAM normalization and real invocation tested; upstream clarification needed |
| GP-PVM-007 | Paper/implementation discrepancy | Code-byte and declared jump-count bounds absent from pinned deblob | JAM bounds and exact edges tested; open PR559 proposes the bounds |
| GP-PVM-008 | Paper/implementation discrepancy | Cross-page store reports a missing higher page before a read-only lower page | Scoped scalar compatibility rule; paper expectation retained in 48 differential witnesses |

## Upstream discussion review —2026-10-21

Reviewed565 issue/PR records across all states, targeted GitHub searches including
comments, candidate PR patches, and129 inline review comments on PR508. This is a
bounded search, not proof that no other discussion exists. Current PR/issue status
was checked separately from our pinned source; merged background is not necessarily
a resolution of the exact witness. No issue or comment was posted by this review.

| Finding | Closest upstream discussion | Disposition |
| --- | --- | --- |
| GP-PVM-001 | [PR201](https://github.com/gavofyork/graypaper/pull/201), merged, introduced the memory exception prose/equation. [Issue446](https://github.com/gavofyork/graypaper/issues/446), closed, addresses unconditional low64KiB protection. | Related history; neither reviewed discussion explicitly settles high-address wrap ordering. |
| GP-PVM-002 | No exact final-byte/exclusive-end report found in the reviewed records and searches. | Still a candidate for a focused report, subject to another duplicate check before posting. |
| GP-PVM-003 | [PR508](https://github.com/gavofyork/graypaper/pull/508), merged, introduced branch-byte pricing. | Related specification history; no exact negative-index/wrapped-target clarification found. |
| GP-PVM-004 | [PR508 prevalidation discussion](https://github.com/gavofyork/graypaper/pull/508#discussion_r2733227344), [reviewer agreement](https://github.com/gavofyork/graypaper/pull/508#discussion_r2735584016), and [final-terminator review](https://github.com/gavofyork/graypaper/pull/508#discussion_r2754119661). | Direct evidence of prevalidation intent; the exact final fallthrough/conditional predicate gap and retained-prefix witness are not explicitly resolved there. |

PR508's author proposed validation before execution; the reviewer agreed. A later
[author comment](https://github.com/gavofyork/graypaper/pull/508#issuecomment-3848643306)
describes invalid conditional destinations as runtime traps, together with requiring
a final block terminator. The remaining question is the precise validation boundary,
not whether upstream had considered prevalidation at all. Preserve these links when
raising GP-PVM-004 rather than presenting it as an entirely new topic.

Other relevant proposals remain **open**:

- [PR555: code-blob format rework](https://github.com/gavofyork/graypaper/pull/555)
  replaces the bitmask and introduces macro blocks. It is a broader pending redesign,
  not an adopted correction of these0.8.0 witnesses.
- [PR559: blob/jump-table limits and cmov dependencies](https://github.com/gavofyork/graypaper/pull/559)
  concerns adjacent validation and gas-model requirements, without settling these exact edges.
- [PR531: PVM working-set](https://github.com/gavofyork/graypaper/pull/531)
  concerns paging/working-set metering; it is not a confirmed fix for final-byte behavior.

Additional **merged** background:
[PR383](https://github.com/gavofyork/graypaper/pull/383) tightened opcode and jump-target
validity; [PR272](https://github.com/gavofyork/graypaper/pull/272) removed wrapping from
host-function memory operations, not scalar instruction accesses. The latter should
not be mistaken for a resolution of GP-PVM-001/002. The source/body/review snapshots
used for this search remain locally under `build/graypaper-issue-review/`.

## Grey implementation review —2026-10-21

Sorpaas's [original Grey repository](https://github.com/bitarray/grey) now contains
only a relocation notice at `bb58d33108b31dcbfe901183e12132702d77fc5e`.
The notice points to JAR, whose GitHub URL now redirects to `alleyos/alley`.
The preserved pre-relocation source revision is
`bc2ba32c45a2dcce1392073f8d3b5874f3045628`; this review reads source and discussions,
without importing code, executing Grey, or changing our dependency pins.

Relevant clarification: closed [Grey issue155](https://github.com/alleyos/alley/issues/155)
reports that branch targets incorrectly split interpreter gas blocks, while merged
[PR154](https://github.com/alleyos/alley/pull/154) aligns the recompiler with GP508's
post-terminator gas blocks. The issue explains why compare-mode tests missed the
difference: transpiled inputs inserted fallthrough at branch targets. This is an
implementation deviation, not a demonstrated paper contradiction, and does not
resolve our negative-target lookup question. Use original raw-byte fixtures to
exercise block partitioning independently of a shared transpiler.

The preserved [program validator](https://github.com/bitarray/grey/blob/bc2ba32c45a2dcce1392073f8d3b5874f3045628/crates/javm/src/program.rs#L277-L301)
checks the last opcode's terminator membership; its
[unit fixture](https://github.com/bitarray/grey/blob/bc2ba32c45a2dcce1392073f8d3b5874f3045628/crates/javm/src/program.rs#L420-L436)
accepts final fallthrough. This is source evidence related to GP-PVM-004, not an
executed third implementation result. Its additional jump-table checks must not
be inferred to be paper requirements.

JAR subsequently chose a different memory model and protocol; merged
[PR197](https://github.com/alleyos/alley/pull/197) changes the memory layout, and
[later workspace removal](https://github.com/alleyos/alley/commit/1dc8753ffb26cf9f302b76a45b00d23d797bb069)
explicitly retires legacy Grey. Current JAR behavior therefore cannot be assumed
JAM0.8.0-compatible. Bounded searches for `PVM`, `graypaper`, `gray paper` and
`discrepancy` found the useful threads above, but no exact resolution of our four
questions; this is not proof that no other discussion exists.

Four [local issue drafts](graypaper-discrepancy-issue-drafts.md) retain exact
witnesses and upstream context for maintainer review and manual posting.

## GP-PVM-001: exception ordering across the address-space boundary

**Paper evidence:** Appendix PVM, Single-Step State Transition,
[text/pvm.tex lines168–179](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L168-L179).
The prose requires immediate panic whenever a required byte is below `2^16`.
The equation instead builds the inaccessible-index set `x`, then tests
`min(x) mod 2^32`; it takes the minimum before reducing the index.

**Minimal witness:** read two bytes beginning at `2^32 - 1`, with the final page
and low page inaccessible. The requested unreduced indices are
`{2^32 - 1, 2^32}`. The second reduces to zero, so the prose implies Panic.
The equation selects `2^32 - 1` first and implies Fault at `0xfffff000`.
The same ordering issue affects writes. If the formal requested indices are instead
intended to be reduced before forming the set, that convention needs to be explicit.

**Pinned PolkaVM:** DynamicMemory `load_impl`/`store_impl` checks exclusive-end
u32 addition first and returns Segfault for an absent final page; a present final
page gives Trap, before store permission checks. See
[interpreter.rs lines1105–1170](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm/src/interpreter.rs#L1105-L1170).
The upstream `dynamic_paging_read_at_top_of_address_space` test uses a four-byte
load at `0xffffffff` and expects final-page Segfault; this is a source-inspected
upstream assertion, not a claimed execution of that Rust test suite.

**Ragnarök disposition and coverage:** the maintainer approved final-page Fault
when absent and Panic when present. Independent scalar cases cover widths1/2/4/8,
permissions and upper address bits in
[the machine suite](../tests/unit/codec/test_pvm_machine.nim).
[Memory stepping](../tests/unit/codec/test_pvm_memory_step.nim) checks all30 memory
forms and paid/exact/insufficient gas; real wrapping load/store checkpoint guests
exercise JAM fault normalization and publication of the saved deletion.
See the [memory contract](pvm-polkavm-memory-order.md) and
[checkpoint contract](pvm-assured-checkpoint-wrapping.md).

**Question to raise:** should any protected wrapped byte force panic, or should an
earlier inaccessible unreduced index fault first? Specify index normalization,
exception priority and the interaction with read-only high pages for stores.

## GP-PVM-002: exclusive-end overflow rejects the mapped final byte

**Paper evidence:** the same memory-access equation and the scalar byte load/store
instruction definitions in
[text/pvm.tex lines384–402](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L384-L402).
A one-byte access at `0xffffffff` requests only that byte. There is no wrapped
protected byte and no requested index outside the32-bit address space.

**Minimal witness and competing results:** map the final4096-byte page read-write,
set its last byte to7, and execute `load_u8` with effective address `0xffffffff`.
Under the paper's requested-byte equation `x` is empty: the load succeeds with7.
Pinned PolkaVM DynamicMemory computes `0xffffffff.checked_add(1)`, which fails,
and returns Trap because the final page exists. A one-byte store to that writable
page similarly succeeds under the paper but traps in PolkaVM. With a read-only
final page, the paper implies successful load and Fault on store; PolkaVM traps
for both. When absent, both models fault at `0xfffff000`.

**Reference evidence:** the overflow branches in the immutable interpreter link
above establish this behavior by source inspection. The upstream top-of-address
four-byte test is not evidence for the one-byte mapped case; do not conflate them.
This discrepancy does not depend on the ordering ambiguity in GP-PVM-001.

**Ragnarök disposition and coverage:** a maintainer-approved compatibility exception
adopts the PolkaVM overflow result, including width1. The independent machine
matrix checks the exact fitting/overflow boundary for each scalar width with
inaccessible/read-only/read-write final pages. It includes the mapped final-byte
Panic assertion and a successful penultimate-byte control. Memory-step fixtures
check guest exits, unchanged registers/memory and charge preservation.
The [executed memory reference](pvm-memory-boundary-reference.md) now freezes90
public-API interpreter results across all11 direct scalar forms and absent/RW/RO
mappings, including final-fitting and exclusive-end boundaries. The original12 byte
load/store records remain unchanged after the count header. Native replay checks every exit, exact fault
page, A0 and complete memory/source preservation. The optional generator is retained
with the exact upstream dependency identities; ordinary tests only replay frozen data.
This confirms the specific reference behavior by execution without claiming a full
upstream test-suite run.

**Question to raise:** is the last byte usable for byte loads/stores? Should memory
validity depend on requested byte indices or on representability of the exclusive
end? Specify the boundary and permission priority for every scalar width. A proposed
fix must say whether to change the paper, PolkaVM, or both; this register does not
assume which is defective.

## GP-PVM-003: branch gas for a negative target

**Paper evidence:** the instruction stream is defined as code with an indefinite
zero suffix in
[text/pvm.tex lines100–104](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L100-L104).
This defines nonnegative indices past the end, not negative indices. Relative
targets add a signed offset to the instruction counter without an explicit modulo;
see [lines432–442](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L432-L442).
The branch latency function indexes both target and fallthrough bytes in
[Gas Cost Tables, lines1172–1188](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L1172-L1188).
Gas is calculated before execution rejects invalid branch destinations. The paper
therefore needs to define this lookup even for an invalid negative target.

**Minimal witness:** JamV1 instruction bytes
`[170, 0, 255, 255, 255, 255, 100, 0, 0]`, opcode-mask bytes `[65, 1]`.
The first conditional branch has a signed displacement of-1 at PC0 and a noncheap
fallthrough byte100. The paper gives no byte at instruction index-1, so its price
cannot be obtained directly from the stated sequence. This is a missing definition,
not evidence that the paper explicitly assigns a different numerical price.

**Pinned PolkaVM:**
[read_args_offset](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm-common/src/program.rs#L733-L735)
wraps the decoded target to u32;
[get_branch_cost](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm-common/src/simulator.rs#L1151-L1181)
treats a missing byte as a prediction hit, giving latency1. A temporary public-API Rust probe executed this literal
witness against the pristine pinned JamV1 parser and Full/L2Hit simulator and
returned block cost1. This was not a full upstream test-suite run. Its source,
locked dependencies and output are retained locally under ignored
`build/polkavm-oracle-probe/` and `build/polkavm-oracle-probe-run.log`.
No Rust implementation or probe is part of the production VM.

**Ragnarök disposition and coverage:** independent bounded arithmetic wraps the
pricing target to u32, then uses the existing zero-suffix byte lookup. The
[gas corpus generator](../tests/pvm_gas_reference.py) and native gas suite cover
all16 conditional branch opcodes at-1,-128 and INT32_MIN, with noncheap
fallthroughs. All1776 records pass, including48 new cases; all1728 previous
records remain byte-identical. Step/execution fixtures cover actual invalid-target
panic after successful prefixes, with gas and source aliases preserved. See
[the branch-cost contract](pvm-polkavm-branch-cost.md) for hashes and exact limits.
This does not establish general parity of static-target execution arithmetic.

**Question to raise:** should relative targets be normalized modulo `2^32` for gas
lookup, or should the instruction sequence explicitly define negative-index bytes?
Specify the price before invalid-target panic and retain an executable malformed-
destination witness. The paper's memory latency25 is retained; generic PolkaVM
cache models and its default gas mode are not alternative protocol specifications.

## GP-PVM-004: final fallthrough and conditional rejected before execution

**Paper evidence:** Appendix PVM Basic Definition,
[text/pvm.tex lines51–70](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L51-L70),
accepts a valid instruction partition whose final opcode belongs to T.
[Basic Blocks, lines106–138](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L106-L138)
includes fallthrough and conditional branches in T.
[Static/conditional checks, lines246–260](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L246-L260)
then panic during execution when a successor is not a basic-block start.

**Minimal witnesses:** code `[51,7,7,1]`, mask `[9]`, or
`[51,7,7,170,0,253]`, mask `[9]`. The first instruction loads r7=7; the final
instruction is fallthrough or register equality targeting entry0 with a missing
fallthrough. For the paper's complete framing, prepend `[0,0,4]` or `[0,0,6]`
respectively to code, then append mask. Entry0 is valid. With prepaid gas and
r7 initially99, the paper permits the prefix then returns Panic with r7=7.
`[51,7,7,0]`, mask `[9]`, is the matching trap-ending positive control.

**Executed pinned PolkaVM evidence:** public ProgramParts/ProgramBlob parsing
succeeds for all three; `validate_code_with_isa(ISA_JamV1)` returns Err at4/6 for
the two missing-successor programs. `Module::from_blob` returns ValidationFailed,
so no guest instance executes. The trap control validates, executes and traps at3
with A0/r7=7. The public-API reproducer is retained in the
[validation contract](pvm-final-terminator-validation.md).
Source evidence: [module validation](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm/src/api.rs#L445-L449),
[code validation](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm-common/src/program.rs#L7420-L7432),
and upstream `jam_validate_invalid_fallthrough` in tests.rs. The latter was
source-inspected; our independent public-API witness was executed.

**Ragnarök disposition and coverage:** the maintainer approved strict rejection at
shared JAM initialization as `InvalidProgram`, before memory materialization or any
execution. All22 final members of T are covered at0/1/24 operand padding lengths,
including unreachable suffixes. Static-target runtime validation remains unchanged.
Raw decoding/stepping retain paper behavior. The explicit JAM decoding profile
also applies the rule to inner-machine creation, preserving its HUH failure mapping. Three active native cases verify successful decoding, the actual
prefix, single-step and recursive panic state, exact2/1 step budgets and original
aliases. The separate reference checker requires both observed module rejections
and the successful control. No private feature or upstream/source pin change.
Do not claim these differing expected observations establish loading parity.

**Question to raise:** should a structurally valid final terminator with a missing
successor be rejected by deblob, or admitted and panic when reached? Clarify the
validation rule and preservation of earlier register/memory/host effects.
The local approved exception belongs to JAM preparation, with existing typed failure
mapping and no fabricated guest panic. It does not resolve the formal upstream
question or establish blanket PolkaVM validation precedence.

## GP-PVM-005: jump-table entry widths above four bytes

**Paper evidence:** the pinned [deblob equation](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L49-L56)
encodes the table width z in one byte without a four-byte bound. Width5 with
one zero entry, code `[10,0,50,8]`, mask `[5]`, has complete GP blob
`[1,5,4,0,0,0,0,0,10,0,50,8,5]`. The zero target fits the register domain.
The [raw decoder contract](pvm-program.md) deliberately retains this paper rule.

**Executed pinned PolkaVM:** public `ProgramBlob::from_parts` rejects width5
with `invalid jump table entry size`, even with an empty jump table. The
[source check](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm-common/src/program.rs#L7088-L7093)
restricts widths to0..4. The [retained checker](../tests/reference/polkavm_memory/src/bin/jumps.rs)
covers all256 widths with counts0/1:502 parse rejections above4. The native
paper witness accepts all512 structurally valid blobs; these differing observations
are explicit, not a claim of loading parity.

**Upstream:** open [PR559](https://github.com/gavofyork/graypaper/pull/559)
explicitly proposes limiting each table entry to four bytes, as well as total
code/table limits. This is a direct proposed resolution for the width discrepancy,
not a merged rule in our pinned paper. Do not file a duplicate issue; the
[local draft](graypaper-discrepancy-issue-drafts.md) supplies a precise comment.
The explicit `decodeJamProgram` profile now returns `InvalidProgram` for widths
above4 at outer initialization and HUH at inner-machine creation. Raw paper decoding
continues to accept them. The native512-case suite checks both profiles against the
retained512 public reference observations. No pin changes.

## GP-PVM-006: nonempty zero-width jump tables disappear in PolkaVM

**Paper evidence:** the same deblob equation carries a logical table count
independently of width z. Appendix C's E_0 permits zero, so a declared one-entry,
zero-width table represents `[0]`, consuming no table payload bytes. Complete
blob `[1,0,4,10,0,50,8,5]` has host0 at PC0 and jump_ind r8 at PC2.
At entry2 with r8=2, the paper's dynamic jump selects j[0]=0, continues to PC0
and reaches host0. The empty-table control `[0,0,4,10,0,50,8,5]` panics instead.
A width1 zero entry is the positive control and also reaches host0.

**Executed pinned PolkaVM:** all three raw blobs parse and validate. However,
[JumpTable::len/get_by_index](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm-common/src/program.rs#L5245-L5270)
return0/None whenever the entry width is0, independently of the declared count.
Both width0 cases therefore Trap at PC2; the width1 control returns Ecalli(0)
at PC0. Public module loading succeeds in every case. This is an execution
semantics difference, not merely stricter module rejection or a local resource cap.

**Coverage and disposition:** the [native witness](../tests/unit/codec/test_pvm_jump_table_reference.nim)
checks logical lookup, first-step destination, full host/panic exit and all CPU
source aliases for widths0..255/counts0..1. The public checker verifies502 parse
rejections,6 traps and4 host calls. Production raw execution remains paper-aligned. The explicit JAM profile captures
width0 tables with semantic count0 while retaining the original bytes verbatim;
outer initialization and inner-machine creation both select that profile. The
accepted width0/count1 case now matches PolkaVM's later panic rather than becoming
a preparation failure. Local limits still apply to the declared count. All512 native
raw cases and the JAM profile's502 rejections/6 panics/4 host calls match their
respective expected observations.

**Question to raise:** should z=0 require a zero table count, preserve the declared
number of zero entries, or define a semantically empty table regardless of count?
Please specify deblob and dynamic-jump behavior together. Bounded Gray Paper
issue/PR searches found no exact zero-width resolution; open559's four-byte upper
bound alone does not settle this lower-bound case. A local issue draft is retained.

## GP-PVM-007: code-byte and declared jump-count limits

**Paper evidence:** the pinned [deblob predicate](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L49-L70)
checks framing, opcode partition and entry validity without the implementation's
32 MiB code/16 Mi jump-entry bounds. A complete all-trap program with33554433
instruction bytes and its canonical mask satisfies that predicate. Tiny blob
`[225,1,0,0,0,1,0,1]` declares16777217 zero-width entries, one trap and mask1;
its raw table contains the declared number of zero targets under the paper rule.

**Executed pinned PolkaVM:** [ABI constants](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm-common/src/abi.rs#L28-L33)
and the raw parser reject code above33554432 bytes and declared entries above
16777216, before discarding width-zero entries. The [public probe](../tests/reference/polkavm_memory/src/bin/limits.rs)
checks full present code at limit-1/limit/limit+1, and zero-width declarations at
count limit-1/limit/limit+1/UINT64_MAX. Both accepted code edges validate every
instruction. This is executed parser/validator evidence, not only truncated headers.

**Ragnarök disposition:** following the maintainer's discrepancy compatibility
policy, `decodeJamProgram` applies the same bounds before capture/normalization.
Raw `decodeProgram` retains all seven paper-valid inputs when local policy permits.
Declared counts still consume caller policy first. Native tests cover full code,
raw table lookup, exact boundaries, outer `InvalidProgram`, inner HUH, retained
empty-map aliases and distinct local `LimitExceeded`. The existing raw decoder and
512-case raw/JAM jump-table suites also pass. See the
[module-limit contract](pvm-module-limits.md).

**Upstream:** open [PR559](https://github.com/gavofyork/graypaper/pull/559),
reviewed2026-10-21 at head `a279a738f43fb2399188d752c427e4901a7d1171`,
proposes these exact bounds. The [local draft comment](graypaper-discrepancy-issue-drafts.md)
asks for exact-edge fixtures and declared-count/width-zero interaction. No duplicate
issue is filed, and no paper/upstream revision is adopted. The ABI source digest is
added to the existing PolkaVM source manifest at the unchanged revision.

## GP-PVM-008: missing mappings precede read-only faults in cross-page stores

**Classification:** paper/implementation discrepancy, independent of the protected
low-memory and exclusive-end overflow findings. The Gray Paper prose and equation
agree for this nonwrapping, nonprotected input.

**Pinned paper:** GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
[`text/pvm.tex`, lines 168–178](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L168-L178).
The first inaccessible write index is the minimum index outside writable memory.
Read-only and missing mappings both fail that predicate.

**Minimal witness:** store an immediate u16 zero at `0x10fff`, followed by a trap.
Page `0x10000` is present/read-only; page `0x11000` is absent. Literal JAM code and
mask are `[31,4,255,15,1,0,0,0,0,0,0]` and `[1,4]`; the complete blob prepends
`[0,0,11]`. No branch, wrapping address or gas shortage is involved.

| Observation | Gray Paper | Pinned PolkaVM interpreter |
| --- | --- | --- |
| Exit | Fault | Segfault / native Fault |
| Fault page | `0x10000` | `0x11000` |
| Registers and memory | Unchanged | Unchanged |
| After mapping the higher page | Still faults on lower read-only page | Then faults on lower read-only page |

The initial public checker failed at corpus row 234: actual page 69632, expected
paper page 65536. Source evidence is
[`DynamicMemory::store_impl`](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm/src/interpreter.rs#L1174-L1227):
the two-page branch resolves missing mappings before testing read-only permissions.
If both pages exist, the lower read-only page wins; if both are absent, the lower
missing page wins. The public `Segfault.is_write_protected` bit distinguishes those
cases and is checked in the expanded reference matrix.

**Local disposition:** follow the maintainer's instruction to document discrepancies
and match PolkaVM fixtures. Scalar stores now check missing mappings before
writability for nonprotected, nonoverflowing two-page ranges. Existing protected-low
and exclusive-end rules remain earlier checks. Loads, successful writes, registers,
gas and atomic source ownership are unchanged. This is an explicit scoped exception,
not a change to the paper-derived expected fault or general implementation precedence.

The independent `pvm-memory-access.bin` corpus retains the literal GP fault and all
original registers. Native and public probes apply an explicit GP-PVM-008 adapter
to exactly 48 rows across all 12 multi-byte store forms. Controls include every
permission pair, the two read-only pages case, lower-absent/higher-read-only,
noncrossing accesses, all load forms and untouched bytes after refusal. See the
[complete scalar memory matrix](pvm-memory-access-reference.md).
No upstream duplicate search or issue posting is claimed for this newly found case.
A local issue draft is prepared for the maintainer; a normative clarification remains open.

## Reproducing the local fixture evidence

From a provisioned checkout with the pinned dependencies, run:

```sh
make unit SUITE=pvm_machine
make unit SUITE=pvm_memory_step
make unit SUITE=pvm_assured_checkpoint_wrap_load
make unit SUITE=pvm_assured_checkpoint_wrap_store
make unit SUITE=pvm_gas
make unit SUITE=pvm_step
make unit SUITE=pvm_execution
```

These assert the documented compatibility behavior, not that the paper has been
corrected. Pin checks use `python3 -m unittest discover -s tests -p test_spec.py`.
For an upstream GP-PVM-003 report, the complete public-API core of the targeted
Rust probe is below; build it against the pinned `polkavm-common` with `alloc`,
using the upstream lockfile versions (`picosimd0.9.6` with `ops`). Preserve the
upstream source and toolchain; this is optional reference evidence, not a project
build prerequisite.

```rust
use polkavm_common::program::{InstructionSetKind, Instructions};
use polkavm_common::simulator::{CacheModel, Simulator};
use polkavm_common::utils::{GasVisitorT, B64};

fn main() {
    let code = [170_u8, 0, 255, 255, 255, 255, 100, 0, 0];
    let mask = [65_u8, 1];
    let isa = InstructionSetKind::JamV1;
    let mut sim = Simulator::<B64, ()>::new(&code, isa, CacheModel::L2Hit, ());
    for instruction in Instructions::new_bounded_known_boundary(isa, &code, &mask, 0) {
        // Stop at the first completed block; following blocks are not part of this witness.
        instruction.visit_parsing(&mut sim);
        if let Some(cost) = sim.take_block_cost() {
            assert_eq!(cost, 1);
            println!("negative_target_cost={cost}");
            return;
        }
    }
    panic!("no completed block");
}
```

## Cross-checks with no new discrepancy

The [executed arithmetic cross-check](pvm-register-reference-crosscheck.md) passes
all38977 unchanged independent rows across85 register-only opcodes, comparing the
exact trap PC and all13 registers against pinned PolkaVM interpreter/JamV1. These
expectations remain Gray Paper-derived; no row was changed to obtain parity.
The [executed gas cross-check](pvm-gas-reference-crosscheck.md) also passes all1784
independent block prices under JamV1/L2Hit, retaining the paper's25-cycle memory
profile. Exact local simulation ceilings remain checked by the native gas suite.
The [control-flow corpus](pvm-load-jump-reference.md) compares all1800 complete
conditional/load-and-jump paths and every register. The
[metered fault-retry cases](pvm-metered-fault-retry-reference.md) retain one paid
charge across22 scalar repair scenarios; [host resumption](pvm-metered-host-reference.md)
checks nine programs with two host replies and exact shared budgets. Their contracts
explicitly map reference causing-PC/identifier representations to GP observations.
These results do not imply unrestricted PVM conformance.

## Related findings outside this PVM increment

Existing evidence remains in its owning records rather than being duplicated here:
[state clarifications](state-clarifications.md) records request-namespace overlap,
serialization-width discrepancies and work-report tuple ordering, including dated
upstream dispositions; [signing domains](signing-domains.md) records token notation
interpretation. Their historical issue statuses are not freshly rechecked by this
PVM documentation change. This index is not a statement that every interpretation
is an unresolved paper defect.

## Required future PolkaVM fuzzing CI

Maintainer requirement: integrate the pinned PolkaVM fuzzing coverage as a separate
CI job once the differential execution boundary is ready. This is a required
follow-up, not coverage supplied by today's deterministic public-API probes.
The pinned [upstream driver](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/ci/jobs/fuzz.sh)
inventories seven targets: generic allocator, shared-memory allocator, linker,
PVM execution, program-blob parsing, extended decoding and page sets.

The job must inventory every upstream target, run applicable reference targets
with their own pinned toolchain/lockfile and Linux backend requirements, and bridge
JAM-relevant generated programs into the Nim implementation. Running only upstream
Rust targets is not evidence of Nim parity. Preserve exact failing inputs, seeds,
reference profile/backend and minimized regressions; replay those deterministically
in the ordinary native suite. Keep specification discrepancies visible and compare
through the selected compatibility boundary. CI output must distinguish unsupported
platforms, local limits and guest exits. Pin changes require explicit review;
production remains independent of the Rust reference and fuzz harness.
