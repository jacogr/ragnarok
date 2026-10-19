# Accumulation provide host dispatch

## Scope and authority

Implement Omega_Aries (27) from pinned Gray Paper 0.8.0 revision
`07f041dabd073f9018b418e9ee72e79dd2185401`, `text/pvm_invocations.tex`,
accumulate-function affordability preamble, `fnmemgas` and the provide row;
`text/definitions.tex` fixes base 3980 and rate 2264 per 1024 bytes.

Charge the full register-width length before row-specific checks. Then reject
non-uint32 lengths with HUH, panic on unreadable guest ranges, select self for
UINT64_MAX or an exact uint32 target otherwise, and retain only requested,
nonduplicate target/blob pairs. Success returns OK; absent/out-of-domain targets
return WHO; unrequested and duplicate pairs return HUH. All protocol responses
preserve unrelated registers and memory. Private regular effects change only on
success; checkpoint and older results remain immutable.

Explicit provision item/per-blob/aggregate policy extends the existing dispatcher
limits. Local copy/capture limits, malformed backing and backend failure expose no
partial execution. Existing callers default to zero provision capacity. Compute
full-width gas exactly before subtraction, refusing locally with GasRangeExceeded
only when terminal debt exceeds the existing signed-negative machine domain.
No invalid-length path may wrap the cost or alias a truncated target/address.

Completion witnesses use real guest execution for funded/underfunded charges,
rounding boundaries, invalid lengths, high-bit/self targets, memory precedence,
empty/nonempty requested bytes, duplicate status, source/backend failures, local
limits, checkpoint/termination histories, normalized provision extraction, the
adopted nonempty hash-return projection, ownership and 1,000 release cycles.
This slice neither fulfills requests nor publishes preimages/state. The existing
32-byte-return/nonempty-provision gate is removed by the [scoped X projection](pvm-hash-return-provisions.md);
[heap integration](pvm-accumulation-heap.md) separately adopts merged #533/#538 fixes.


## Implementation and ownership

`executeAccumulationMachine` accepts an optional explicit
`AccumulationProvisionLimits`. Its default gives no retained provision capacity;
other host calls keep their existing behavior. `copyLimit` separately bounds
transient guest-byte copying; the item/per-blob/aggregate policy bounds hash/scan
work and immutable retention through `recordAccumulationProvision`. No failure
publishes the callback-local candidate effects. Normalized output owns the selected
context, and its provision extraction returns independent bytes.

The gas helper decomposes `ceil(2264*z/1024)+3980` into two bounded limbs before
subtracting available gas. It supports costs above uint64 when the resulting
negative balance fits the machine's existing [-2^63, 0) representation. A larger
debt returns local `GasRangeExceeded`; it is neither a guessed guest response nor
clamped debt. The established positive/signed-gas specification gate is unchanged.

The native witnesses use literal independent gas expectations at 0/1/1023/1024/
1025 bytes, both sides of the uint32-length boundary, a cost above uint64 and the
exact signed-negative limit. Actual guest programs verify memory-before-WHO and
length-before-memory ordering, self/full-width targets, empty and cross-page reads,
unrequested/duplicate histories, distinct target pairs, all local budgets, malformed
backing and each of the two backend hash failures. Checkpoint/termination tests
verify selected provision sets and reach the existing hash-return gate with a real
nonempty set. Complete-map inputs and request records are retained; provide does
not insert raw preimages or fulfill request histories.

## Next boundary

[Lookup (3)](pvm-accumulation-lookup.md) now reads existing account preimages;
remaining account host calls (read/write/info), grow_heap's specification
decision and selected-provision publication remain subsequent increments. This is
not full Psi_A, authenticated block execution or persistent state publication.


## Local verification (2026-10-19)

After native stack synchronization, this layer includes master `610f99e` and its
per-suite native preparation changes. The supported `tools/native_tests.py --suite`
entry point passed `pvm_accumulation_provide`, `pvm_accumulation_dispatch`,
`pvm_accumulation_outcome`, `pvm_accumulation_machine` and `pvm_accumulation_fetch`.
The selected profiles prepared only their required crypto provider, with no
unrelated Rust/QUIC libraries or integration corpora. Every suite passed its
1,000-cycle ARC witness; provide occupied memory was 1,052,032 bytes before/after.

Nine affected runtime result probes and five dispatch/outcome privacy probes
passed through the existing harnesses. Fifty selected Python tests covered the
verification inventory, native unit/preparation selection and guard/failure-family
registration. Inventory, pinned Nim/Rust formatting and diff checks passed.
Full logs and targeted guard evidence are under `build/pvm-provide/`, including
`native-final.log`, four consumer logs, `guards.log`, `targeted-results.json`,
Python logs and `format-check.log`. Final changes after native verification were
comments/documentation only. Complete local six-group verification and Linux CI
are not claimed.
