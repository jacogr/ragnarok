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
| GP-PVM-004 | Paper/implementation discrepancy | Final fallthrough/conditional: runtime panic versus module rejection | Both behaviors reproduced; local policy decision pending |

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
The [executed memory reference](pvm-memory-boundary-reference.md) now freezes12
public-API interpreter results for byte loads/stores at the final and penultimate
addresses with absent/RW/RO mappings. Native replay checks every exit, exact fault
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

**Ragnarök disposition and coverage:** preserve current paper behavior pending a
scoped decision. Three active native cases verify successful decoding, the actual
prefix, single-step and recursive panic state, exact2/1 step budgets and original
aliases. The separate reference checker requires both observed module rejections
and the successful control. No private feature or upstream/source pin change.
Do not claim these differing expected observations establish loading parity.

**Question to raise:** should a structurally valid final terminator with a missing
successor be rejected by deblob, or admitted and panic when reached? Clarify the
validation rule and preservation of earlier register/memory/host effects.
Locally, choosing strict rejection also requires deciding whether it belongs in
raw decoding, JAM preparation or an explicit reference-loader adapter, and how
that failure is represented. This choice remains pending; prior approved memory
and gas exceptions do not settle it.

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
The [executed gas cross-check](pvm-gas-reference-crosscheck.md) also passes all1776
independent block prices under JamV1/L2Hit, retaining the paper's25-cycle memory
profile. Exact local simulation ceilings remain checked by the native gas suite.
These results do not imply unrestricted PVM conformance.

## Related findings outside this PVM increment

Existing evidence remains in its owning records rather than being duplicated here:
[state clarifications](state-clarifications.md) records request-namespace overlap,
serialization-width discrepancies and work-report tuple ordering, including dated
upstream dispositions; [signing domains](signing-domains.md) records token notation
interpretation. Their historical issue statuses are not freshly rechecked by this
PVM documentation change. This index is not a statement that every interpretation
is an unresolved paper defect.
