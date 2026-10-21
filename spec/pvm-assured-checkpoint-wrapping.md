# Checkpointed actual guests preserve the wrapping-access gate

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/pvm.tex` memory-exception prose/equation at lines168–178 and
`text/pvm_invocations.tex` exceptional checkpoint selection; vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Scope: independently author ReadCheckpointWrapLoad/Store before refinement,
root/signing and original execution. Both use the genuine list-count branch to
halt at count1 after creating eleven bytes. At count2, delete, checkpoint absence,
read NONE, restore eleven regular bytes, then actually load_i16/store_u16 atMAX64.
The two physical bytes are0xffffffff and0. No memory, report, completed outcome or
terminal state is patched. First execution is the successful control.

The pre-existing [machine gate](pvm-machine.md#explicit-unresolved-specification-gate)
is reached through real assured execution: the high page is inaccessible, while
the wrapped byte is protected. Pinned prose says a required low byte always
panics; the equation selects the first inaccessible original index and yields a
high-page fault. The implementation must retain AmbiguousAccessOrder as a local
refusal. Neither interpretation is adopted by this test, and no pins change.

Completion: original Halt/Regular and committed bytes, genuine count2 local
RunnerFailure/DispatchFailure/ExecutionFailure/AmbiguousAccessOrder, exact28/27
step distinction, calls3/4 and copy11/10 precedence, unchanged complete original
state and chain view, and1000 failed-owned-invocation ARC releases per mode.
A guest panic would incorrectly complete and permit checkpoint publication;
these tests reject that alternative. Failed results carry no completed successor.
Run predecessor checkpoint/consumer, harness/inventory and formatting checks.

Further consensus behavior for this access needs maintainer-approved authority:
prose-first panic, formal first-inaccessible-index fault, or a compatible upstream
clarification/pin adoption. Until then preserve the local gate. M1 framing is
complete; full state serialization, whole-block parity and chainspec equivalence
remain open.

Observed: genuine original count1 guests halt in Regular and retain the complete
eleven-byte value. Both count2 guests reach the expected nested
AmbiguousAccessOrder refusal. Steps27 refuses before the disputed instruction;
steps28/copy11 reaches the gate. Calls3/4 and copy10 instead refuse at the actual
preceding read/restoration. Both suites run1000 failures with472304/472304
occupied bytes, preserve exact original maps/views and expose no completed owner.
The helper semantic check,37 native-harness tests and inventory pass.

## Proposed next boundary decision

Both competing scalar exits become Panic/Exceptional under Psi_M followed by
accumulation selection; see [outcome normalization](pvm-accumulation-outcome.md).
A possible next increment would explicitly approve normalization at that
invocation boundary while preserving AmbiguousAccessOrder for raw scalar/step
APIs. This is a proposal for maintainer feedback, not implemented behavior.

An implementation cannot simply catch the current error and manufacture a
terminal result: failed stepping deliberately discards partial CPU state and
unpublished block charges. It would need a scoped executor path preserving exact
paid block gas, all earlier host effects, atomic scalar failure and selected
checkpoint ownership. Every other local budget/specification refusal must remain
a local failure. Alternatively, keep the existing gate and continue independent
PVM paths. No authority choice or dependency upgrade is implicit in this PR.

Final verification: the successful protected-memory checkpoint control passes
1000 full successors at753888/753888 bytes, and the computed-storage consumer
passes1000 cycles at2933856/2933856 bytes. Inventory recognizes219 failure
families/2562 probes/337 suites; pinned formatting passes2582 Nim sources and the
Rust crate. All results are local checked-release macOS evidence; remote Linux
CI was not requested. Production source and protocol pins are unchanged.
