# Storage reads observe earlier guest writes

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, storage
read/write hosts and regular accumulation effects; vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Author FetchReadBack before original refinement/signing/computation. Fetch the
actual input-list count into RW, write [count,22,23], read that self key into
separate initially zero RW bytes, then rewrite the key from those read bytes.
Historical count1 must commit[1,22,23]; assured count2 must commit[2,22,23].
Reading the parent instead of the current regular effects would return old1 or
absence, making these independent storage oracles fail. No memory, report,
terminal, response or completed source is patched. Self uses target MAX64.

This new guest needs24 instructions/four hosts. Only this new mode receives a
bounded32-step policy before its original execution and in the new assured test;
older mode policies/bytes stay unchanged. Original funding50, capture3, gas10000
then20000, host ceiling4 and all protocol parameters remain unchanged. Compact
new-mode exit encoding preserves the existing single-byte code envelope.

Completion requires actual Halt/Regular, one selected key/three value bytes for
two real writes, unchanged balance50/footprint38/item1/code, and full canonical
composition/publication checks for timestamp3/history3/activity reports2/actual
gas/all29 parameters/aliases/finality1. Fetch1 costs288; write1/3 costs2447;
read1/3 costs2410; second write2447. One syntactic block costs at most997,
giving gas>7592and<=8589, below the original10000. Original and next actual gas
must be equal because only the fetched count changes.

Copy3 and one selected key/three final bytes must succeed. Calls2 refuses the
read after the first write; calls3 refuses the second write after the read.
Final bytes2/key0 and zero captured-key provenance must refuse precisely.
Run1000 full execution/composition/publication ARC cycles, affected predecessors,
affected semantic checks, registration/tooling and pinned formatting.

Next: exercise storage-read clipping and full returned lengths.
M1 framing complete; full state serialization, whole-block parity and full
chainspec equivalence remain open.

Observed local evidence: original and next actual Halt/Regular persist[1,22,23]
and[2,22,23] respectively. Both execute actual fetch/write/read/write and use
equal actual gas within the independent7592..8589 bounds. Two writes retain one
selected proof key and three final bytes, account balance50/footprint38/item1 and
original code. Full composition/publication/alias/parameter/finality checks pass.
Copy3/steps24 succeeds; steps23 refuses StepLimitExceeded. Calls2 and3 each refuse
HostCallLimitExceeded. Copy2 refuses DispatchLimitExceeded; final bytes2/key0
refuse Completion/Batch/LimitExceeded; zero captured-key provenance refuses
UnsupportedAccountEffects. No local refusal becomes a guest panic or partial
canonical publication.

One thousand full successors retain754224/754224 occupied bytes. All eight
predecessor native groups pass again at1000 cycles: branch687792, delete753424,
tail753792, ranges938352, list1459632, individual inputs1406672, original
storage2933856 and outcomes3162032 bytes unchanged. Only the guest factory and
original-execution helper change among3458 predecessor inputs;3456 are identical.
All three affected semantic checks,35 tooling tests, inventory194 families/2436
probes/273 native suites, and formatting2339 Nim sources plus Rust pass. Local
checked-release macOS evidence; remote CI remains separate.
