# Gray Paper PVM issue drafts

Prepared for maintainer review and manual posting; nothing has been filed upstream.
These are separate questions, not a request to adopt all PolkaVM implementation details.
Resolved upstream entries are disposition notes rather than new issues to post.
The [discrepancy register](graypaper-discrepancies.md) retains the full evidence and
local compatibility decisions. Each draft below is intended to stand on its own.

## GP-PVM-001 — Clarify wrapped memory access exception priority

Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
[Single-Step State Transition](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L168-L179),
says a required byte below2^16 immediately panics, while the equation takes the
minimum inaccessible index before applying modulo2^32.

For a two-byte load at0xffffffff with both the final page and page0 inaccessible,
the unreduced requested indices are {0xffffffff, 0x100000000}. Reducing all required
indices first exposes protected byte0 and implies Panic. Taking the stated minimum
first instead implies Fault at0xfffff000. The same question applies to stores.

Pinned PolkaVM0.37.0 `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`
[DynamicMemory](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm/src/interpreter.rs#L1105-L1170)
faults on the absent final page; when that page is present it traps.

Could the specification explicitly define whether indices are reduced before
forming the inaccessible set, and which exception takes precedence? Please include
absent, read-only and writable final-page cases. Merged
[PR201](https://github.com/gavofyork/graypaper/pull/201) introduced the formalization;
[issue446](https://github.com/gavofyork/graypaper/issues/446) establishes the protected
low zone but does not settle this ordering question.

## GP-PVM-002 — Define whether the final addressable byte is usable

Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
[memory exceptions](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L168-L179)
and [scalar operations](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L384-L402),
validate the bytes actually accessed. A one-byte load at0xffffffff with the final
page mapped RW and its last byte7 therefore succeeds with7. A byte store to that
RW page also succeeds. No requested byte wraps into the protected zone.

Pinned PolkaVM0.37.0 `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`
[checks the exclusive end in u32](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm/src/interpreter.rs#L1105-L1170).
The addition0xffffffff+1 fails, so both operations Trap on a mapped final page.
With an RO final page it also traps on both, whereas the paper implies successful
load and Fault on store. With an absent final page both fault at0xfffff000.

Our public interpreter probe executes all12 combinations of byte load/store,
address0xfffffffe/0xffffffff and absent/RW/RO final pages. The penultimate byte is
a positive control; the frozen final-byte results confirm the behavior above.
[Probe source](../tests/reference/polkavm_memory/src/main.rs) and
[reproduction contract](pvm-memory-boundary-reference.md) are available.

Should admissibility depend on requested byte indices or representability of the
exclusive end? Please specify the final fitting address for each scalar width and
permission priority. This is independent of wrapped-byte ordering: a one-byte
access here has no wrapped required byte. We do not assume whether the paper,
PolkaVM, or both should change. [PR272](https://github.com/gavofyork/graypaper/pull/272)
changed host-function ranges, not these scalar operations.

## GP-PVM-003 — Define gas lookup for negative relative branch targets

Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` defines an
[infinite zero suffix](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L100-L104)
for nonnegative code indices. Its
[branch latency](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L1172-L1188)
also indexes a relative target that can be negative. Gas is needed before execution
rejects that destination, so the invalid destination still requires a defined price.

Minimal JamV1 code: `[170,0,255,255,255,255,100,0,0]`; mask `[65,1]`.
At PC0 the signed displacement is-1 and the fallthrough byte is100. The paper
does not define code[-1]; this is an undefined lookup, not an explicit competing
numerical price.

Pinned PolkaVM0.37.0 `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`
[normalizes the target to u32](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm-common/src/program.rs#L733-L735)
and its [branch-cost function](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm-common/src/simulator.rs#L1151-L1181)
uses latency1 for the missing byte. A public Full/L2Hit simulator probe returns
block cost1 for this witness; the retained checker also agrees with all1776 rows
of our independent gas corpus, including48 negative-target cases.

Should pricing targets be reduced modulo2^32, or should negative code indices
have an explicit definition? Please define the gas charge before destination
panic, including untaken conditional branches. Merged
[PR508](https://github.com/gavofyork/graypaper/pull/508) supplies the gas model;
we found no explicit resolution of this negative-index question in the reviewed
threads. Generic PolkaVM cache/default gas models are not being proposed as
alternative JAM costs.

## GP-PVM-004 — Reconcile final terminator admissibility with module prevalidation

Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
[structural validation](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L51-L70),
accepts a complete instruction partition whose last opcode belongs to T.
[T includes fallthrough and conditional branches](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L106-L138).
These instructions can lack a successor at the end of code, which the
[runtime checks](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L246-L260)
turn into Panic when reached.

Three literal witnesses, entry0, initial r7=99:

| Case | Code | Mask | Full GP blob |
| --- | --- | --- | --- |
| Control | `[51,7,7,0]` | `[9]` | `[0,0,4,51,7,7,0,9]` |
| Final fallthrough | `[51,7,7,1]` | `[9]` | `[0,0,4,51,7,7,1,9]` |
| Final conditional | `[51,7,7,170,0,253]` | `[9]` | `[0,0,6,51,7,7,170,0,253,9]` |

The load prefix writes r7=7. The conditional's signed-3 taken target is valid
entry0; its missing fallthrough is the isolated defect. Under the stated paper
rules all three decode and execute the prefix before eventual Panic, retaining7.
Prepaid gas in our raw interpreter witness isolates this from pricing.

Pinned PolkaVM0.37.0 `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` parses
all three raw blobs. Its
[code validator](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm-common/src/program.rs#L7420-L7432)
rejects the latter two at offsets4/6, and
[module loading](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm/src/api.rs#L445-L449)
returns ValidationFailed before any execution. The control validates and traps
at3 with A0/r7=7. The retained [public-API checker](../tests/reference/polkavm_memory/src/bin/validation.rs)
executes these observations without private features or source patches.

Merged [PR508's prevalidation proposal](https://github.com/gavofyork/graypaper/pull/508#discussion_r2733227344)
and [reviewer agreement](https://github.com/gavofyork/graypaper/pull/508#discussion_r2735584016)
establish prior intent to reject malformed modules before execution. Could the
formal admissibility rule explicitly require a final terminator with no required
fallthrough, or otherwise resolve this example? Please specify the failure stage
and JAM invocation result/gas normalization, including preservation of earlier
register, memory and host effects if runtime handling is intended.

For compatibility we have approved rejecting these at JAM guest preparation while
preserving the paper-aligned raw interpreter. That local policy is not evidence
that the paper already defines the stricter predicate.

## GP-PVM-005 — Historical comment on PR559 (subsequently merged)

[PR559](https://github.com/gavofyork/graypaper/pull/559) directly addresses a
reproducible difference with Gray Paper0.8.0
`07f041dabd073f9018b418e9ee72e79dd2185401`: its deblob predicate currently
permits z=5, whereas PolkaVM0.37.0
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` rejects widths above4.

Minimal complete GP blob: `[1,5,4,0,0,0,0,0,10,0,50,8,5]`.
It has one zero table entry encoded in five bytes and valid host0/jump_ind code.
Our independent paper decoder accepts it. Public PolkaVM ProgramParts parsing
returns `invalid jump table entry size`; even count0 with width5 is rejected.
The full width0..255/count0..1 matrix confirms502 such rejections.

Please retain explicit malformed-width fixtures alongside the new predicate,
including an empty table with oversized width. The separate zero-width/nonzero-
count question below also needs a defined result; a four-byte upper bound alone
leaves it open.

## GP-PVM-006 — Define zero-width jump-table count semantics

Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
[deblob](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L49-L56),
carries a table count and one-byte entry width separately. Appendix C permits
E_0(0), so a nonempty sequence of zeros needs no table payload at width0.

Complete literal blobs, entry2, r8=2:

| Case | Blob | Paper execution |
| --- | --- | --- |
| Empty table | `[0,0,4,10,0,50,8,5]` | Panic at jump PC2 |
| One zero-width entry | `[1,0,4,10,0,50,8,5]` | Jump to PC0, then host0 |
| One width1 zero entry | `[1,1,4,0,10,0,50,8,5]` | Jump to PC0, then host0 |

PolkaVM0.37.0 `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` publicly parses,
validates and loads all three. Its
[JumpTable implementation](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm-common/src/program.rs#L5245-L5270)
returns no entries for any width0 table. Executing through the public interpreter
therefore gives Trap at2 for both width0 cases and Ecalli(0) at0 for the width1
control. This is an executed result, not an inference from the parser alone.

Should width0 require count0, retain the count of zero entries, or explicitly
mean an empty table? Please define both acceptance and dynamic lookup. Rejecting
all nonempty width0 tables would itself differ from current PolkaVM's successful
module load and later trap. [PR559](https://github.com/gavofyork/graypaper/pull/559)
proposes an upper width bound but does not resolve this case.

## GP-PVM-007 — Historical boundary-fixture comment on PR559 (subsequently merged)

[PR559](https://github.com/gavofyork/graypaper/pull/559), now merged2026-10-21, adds code and jump-count
bounds missing from our pinned Gray Paper0.8.0
`07f041dabd073f9018b418e9ee72e79dd2185401` deblob predicate.
Pinned PolkaVM0.37.0 `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` already enforces
33554432 instruction bytes and16777216 declared entries.

The smallest count witness is `[225,1,0,0,0,1,0,1]`: count16777217, width0,
code length1, trap, mask1. The paper's raw decoder accepts its logical zero table;
PolkaVM rejects the declared count even though width0 otherwise becomes an empty
table. Counts16777215/16777216 parse and validate;16777217 is rejected.

For the code bound, full present all-trap code and canonical all-start masks at
33554431/33554432 bytes parse and validate in PolkaVM;33554433 is rejected. These
are fully materialized test programs rather than truncated declared-length probes.
Our independent raw decoder accepts all three; the JAM compatibility profile now
follows PolkaVM. The retained public checker and native tests also cover the
UINT64_MAX zero-width declaration without allocating a logical table.

Please preserve both exact-edge fixture families and specify that the code bound
counts instruction bytes, independently of framing/table/mask bytes. The entry
bound must state whether it applies to the declared count before width-zero
normalization; the current implementation checks that declaration first. This
interacts with the separate GP-PVM-006 zero-width interpretation question.

## GP-PVM-008 — Clarify missing-page versus read-only fault priority

Gray Paper 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
[Single-Step State Transition](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L168-L178),
selects the minimum required write index outside writable memory. Both read-only
and missing pages are nonwritable under that predicate.

Consider `store_imm_u16(0x10fff, 0)`: page `0x10000` is read-only and page
`0x11000` is missing. Literal code `[31,4,255,15,1,0,0,0,0,0,0]`, mask `[1,4]`,
blob prefix `[0,0,11]`. The final zero opcode is a real trap after the store.
The paper selects Fault `0x10000`; pinned PolkaVM 0.37.0
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` selects Segfault `0x11000`.
Registers and memory remain unchanged in both cases.

The interpreter's
[two-page store branch](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm/src/interpreter.rs#L1174-L1227)
checks presence of both pages before their read-only flags. With both pages present
and read-only it selects the lower page, matching the paper. This difference occurs
without wraparound, protected memory or exclusive-end overflow.

Should missing pages take priority over an earlier read-only write fault, or should
all nonwritable bytes participate in one minimum-index selection? Please specify the
fault-address rule, since it determines which page the environment repairs first.
Our local deterministic cross-check exercises all scalar memory forms and retains
48 paper/reference differences with unchanged original paper expectations.

Prepared locally only; a duplicate check is still needed before maintainer posting.

## GP-PVM-009 — Resolved by existing PR554; do not file a duplicate

Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
[three-register arguments](https://github.com/gavofyork/graypaper/blob/07f041dabd073f9018b418e9ee72e79dd2185401/text/pvm.tex#L629-L640),
saturates the complete second operand byte to r12. Pinned PolkaVM0.37.0
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` masks that byte's low nibble first.

For blob `[0,0,4,190,16,16,0,9]`, r0=7, r1=11, r12=55, add32 produces18.
The paper writes r12; executed PolkaVM writes r0. Byte0xff selects r12 in both;
0x10/0x80 select r0 only under PolkaVM. A program that later returns through r0
can therefore halt under one rule and panic under the other. Aliases also change
some block gas/cycle prices.

Public source evidence:
[RawReg::get](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm-common/src/program.rs#L29-L43)
and [read_args_regs3](https://github.com/paritytech/polkavm/blob/69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa/crates/polkavm-common/src/program.rs#L827-L832).
Our independent cross-check covers all41 opcodes/all256 destination bytes with
separate paper/reference expectations, including1050 gas/cycle differences.

The duplicate check found [PR554](https://github.com/gavofyork/graypaper/pull/554),
merged2026-08-26 as `e5375148597a45a99d31c9aa6bce6c7bf3a48998`. Its exact patch
adds modulo16 before saturation. This resolves the question in later upstream text;
our frozen pin still contains the original equation. Retain this witness/disposition
for the pin-upgrade review, and do not post a duplicate issue.
