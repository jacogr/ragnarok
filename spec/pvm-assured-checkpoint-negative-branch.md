# Negative branch panic retains checkpoint deletion

## Specification and scope

Gray Paper0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, Appendix PVM
Single-Step State Transition and conditional branch validity, defines panic for a
target outside the basic-block set. GP-PVM-003 in the
[discrepancy register](graypaper-discrepancies.md) records the missing negative-index
pricing definition and scoped pinned PolkaVM-compatible price. PolkaVM remains at
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa`; no source pins change.

Author a real register-conditional branch with signed displacement-32768 after
fetch, deletion, checkpoint, absent-key read and eleven-byte regular restoration.
A genuine first input halts and commits the original value; the assured two-input
invocation reaches the negative target and must select checkpoint absence through
Panic/Exceptional. No completed outcome or code/report/root is patched.
This tests canonical publication as a consumer of the earlier gas fix; it does not
change production semantics or broaden the static-target arithmetic interpretation.

## Completion

Reuse the complete checkpoint witness: exact28/27 step boundary, copy11/10,
host-call3/4 refusals, zero selected value bytes, key/provenance limits, actual gas,
metadata, account/code preservation, original protocol parameters, full composition,
history/activity/finality and immutable parent aliases. Require1000 complete
successors with unchanged ARC occupied memory and a distinct evidence key.
Run the new native suite plus an existing checkpoint consumer after the shared
mode extension; check discovery/inventory and pinned formatting.
M1 framing remains complete; full state serialization, whole-block parity and
full chainspec equivalence remain open.

## Observed local verification

The new native suite and the existing wrapping-load checkpoint consumer each pass
1000 full successors with753888 occupied bytes before and after. Exact step/copy/
call/provenance boundaries, canonical publication and original aliases remain
asserted. Inventory passes219 failure families/2562 probes/338 native suites;
pinned formatting passes2582 Nim sources and the Rust crate. Evidence is local
checked-release macOS/ARC/Clang LTO, not remote Linux CI. Logs are retained under
`build/pvm-negative-checkpoint-*`.
