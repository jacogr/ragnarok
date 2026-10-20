# Input-controlled panic retains a checkpointed deletion

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, input
fetch, checkpoint assignment, storage reads/writes and exceptional selection;
vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Author ReadCheckpointPanic before original computation/signing. Fetch the real
list count, load it into r6, delete key11, then checkpoint the absent state.
Read the same explicit service42/key with request3 and invalid destination;
store the full NONE word, then restore [count,22,23]+8xff in regular state.
An actual equality branch halts at count1 and traps at count2. Checkpoint only
changes r7, preserving r6 for the branch. No memory/response/report/terminal/
completed source is patched; every stage uses the actual owned pipeline.

The original count1 Halt/Regular creates eleven bytes. The assured count2 first
deletes that existing key and checkpoints absence, then restores a different
regular value before Panic/Exceptional selects the checkpoint. Final absence
therefore distinguishes checkpoint selection from both the initial parent and
later regular restoration. Account deletion is not storage deletion: preserve
account/balance58/code, with footprint0/items0, one selected proof key and zero
selected value bytes. First execution retains footprint46/item1 and eleven bytes.

Only this new mode receives original funding58/capture11 and a bounded32-step/
five-call policy before first execution, matched by its assured test. Older mode
policies/bytes and all protocol parameters remain unchanged. The actual guest
has28 instructions/five hosts and compact code below128 bytes; original report
gas10000 then20000 remains. Host costs288+2446+103+2410+2449=7696, plus two
blocks at most997 each: actual gas>7696and<=9690, below the first gas credit.

Completion requires actual first Halt/Regular and next Panic/Exceptional,
MissingKey rather than present-empty, zero final-value budget success, steps28
success/27 refusal, calls3/4 refusal before read/restoration, and copy11 success/
10 refusal at the real unselected regular restoration. Planned panic must not
hide local resource refusal. Zero final keys and captured-key provenance refuse
precisely for the selected checkpoint deletion. Verify full composition and
publication: timestamp3/history3/activity reports2/actual gas/all29 parameters,
aliases retain parent storage, finality1. Run1000 full successors and every
affected predecessor, semantic/tooling/inventory/format checks.

This is the thirtieth bounded PR in the authorized batch. Next work requires a
new batch: broader genuine program paths and remaining serialization/parity work.
M1 framing complete; full state serialization, whole-block parity and full
chainspec equivalence remain open.

Observed local evidence: genuine original count1 Halt/Regular creates
[1,22,23]+eight255 bytes with footprint46/item1/balance58. Genuine assured count2
Panic/Exceptional publishes MissingKey with footprint0/items0/balance58/code
preserved. Selected proof retains one deletion key and zero value bytes; the
account survives. Both actual gas charges satisfy7696..9690. Full composition/
publication, timestamp3/history3/activity2/actual gas/all29 parameters/aliases/
finality1 checks pass; the original parent retains its eleven-byte key.

Zero final-value capture and copy11/steps28 succeed. Steps27 refuses
StepLimitExceeded; calls3/4 refuse HostCallLimitExceeded. Copy10 refuses the
actual eleven-byte regular restoration before planned panic. Zero final keys
refuse Completion/Batch/LimitExceeded; zero captured-key provenance refuses
UnsupportedAccountEffects for the selected checkpoint deletion.

One thousand full successors retain753888/753888 occupied bytes. All eleven
predecessor groups pass again at1000 cycles: missing753760, storage tail754688,
read754224, branch687792, delete753424, fetch tail753792, ranges938352,
list1459632, individual inputs1406672, original storage2933856 and outcomes3162032
bytes unchanged. Only guest factory, funding helper and original-execution helper
change among3467 predecessor inputs;3464 remain identical. All four affected
semantic checks,35 tooling tests, inventory194 families/2436 probes/276 native
suites, and formatting2342 Nim sources plus Rust pass. Local checked-release
macOS evidence; remote CI remains separate.
