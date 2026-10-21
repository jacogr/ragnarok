# PolkaVM memory exception ordering adoption

## Specification, scoped exception and pins

The Gray Paper is the primary specification; this is independent Nim implementation
with pinned PolkaVM fixture cross-checks. On2026-10-21 the maintainer approved the
following specific memory exception behavior despite the paper discrepancies, then
clarified that this is not general PolkaVM precedence. See entries GP-PVM-001 and
GP-PVM-002 in the [discrepancy register](graypaper-discrepancies.md) for the exact
prose/equation conflict and the separate mapped-last-byte deviation. This supersedes
the prior local wrapping-access gate at the scalar owner, not by invocation-only
conversion of a local error into panic.

PolkaVM remains pinned at `69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`.
`spec/polkavm-pins.json` records its cross-check role and the SHA-256 of both
`crates/polkavm/src/tests.rs` and `crates/polkavm/src/interpreter.rs`.
GP0.8.0 stays at `07f041dabd073f9018b418e9ee72e79dd2185401` and vectors at
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. No upstream code, compiler,
dependency version or gitlink changes; Rust is not a production PVM dependency.

## Exact rule and source evidence

PolkaVM DynamicMemory::load_impl/store_impl first evaluate
`address.checked_add(length)` in u32. On exclusive-end overflow, a present final
page produces Trap; an absent final page produces Segfault at0xfffff000.
This precedes write-protection checks. Thus even a one-byte access at0xffffffff
faults when the last page is absent and panics when it is present. A read-only
final page also panics on an overflowing store. These edges follow the pinned
implementation rather than an inferred mathematical last-byte convention.

The starting effective address uses its low32 bits. Our retained inaccessible
page images represent absent runtime pages; ReadOnly/ReadWrite images represent
present mappings. Empty/default-owner and scalar-width validation still precede
inspection. On nonoverflow ranges, a required low-memory byte panics and the
first inaccessible or nonwritable page faults. Successful operations preflight
every byte; failed stores publish no partial memory. Instruction gas charging,
source alias preservation and fault repair/retry remain unchanged.

Pinned independent evidence: dynamic_paging_read_at_top_of_address_space uses
load_i32 at0xffffffff and requires recoverable page0xfffff000;
dynamic_paging_read_below_the_guard_threshold requires Trap below0x10000,
including a read crossing upward from0xfffe; dynamic_paging_write_at_page_boundary
variants require exact first-fault pages, no partial stores, and successful retry.
The upper-address-bits test starts atMAX64-3 with width4 and is not a wrapping
witness. Interpreter source establishes the corresponding store and final-page
presence/permission branches. Source inspection is not a claimed Rust test run.

## Completion and maintained boundaries

Require scalar widths1/2/4/8 across the exact fitting/overflowing end, MAX32 and
MAX64, with absent/inaccessible/read-only/read-write final pages and accessible
low-page images. Preserve exact fault addresses, unchanged source pages and
local invalid-owner/width errors. Cross all30 memory instruction forms with
prepaid/exact/insufficient gas: overflow fault or panic retains paid gas/charged
state and original registers/memory; out-of-gas wins before inspection.

Recursive execution must retain successful prefix register/store mutations in
the fault snapshot while source aliases stay unchanged. Both originally authored
checkpoint wrap guests must now complete as Panic/Exceptional after their raw
faults, publish the checkpointed deletion, and retain exact28/27 steps,
copy11/10, host-call/provenance limits, gas, metadata, parameters, full canonical
composition/publication, history/activity/finality and1000 ARC release cycles.
The historical AmbiguousAccessOrder enum alternatives remain compatible but are
not emitted by current scalar inspection. Other local limits and specification
gates are unchanged. Run affected native suites, provenance/inventory, relevant
harness tests and pinned formatting. M1 framing complete; full state serialization,
whole-block parity and full chainspec equivalence remain open.

## Observed local verification

All seven affected suites pass1000 ARC cycles with unchanged occupied bytes:
pvm_machine124752; pvm_memory_step17664; pvm_execution20288; both wrapping
checkpoint guests753888 each; protected checkpoint753888; computed storage2933856.
The wrapping suites now publish the saved deletion through complete canonical
successors, with the original committed parent and all parameter/gas/alias
assertions retained. Four focused semantic checks pass. Source-pin specification
tests pass3 with1 pre-existing unrelated Bandersnatch parity skip;37 native-harness
tests pass. Inventory remains219 families/2562 probes/337 native suites; pinned
formatting passes2581 Nim sources and the Rust crate. These are checked-release
macOS/ARC/Clang LTO results; remote Linux CI is separate and was not requested.
Exact source/dependency/configuration hashes and logs are retained under
`build/polkavm-memory-*`. No PolkaVM Rust execution is claimed.

Runtime probe follow-through: the former ambiguous-origin misuse input now
produces a valid Fault. Replace that obsolete failure expectation with a genuine
local cycle-limit refusal; retain the same strict value precondition diagnostic.
An explicit fault-origin driver invocation succeeds as a positive control.
Non-fault origins continue rejecting fault-page access. Verify all six negative
process cases and the positive control under the checked-release build profile.
