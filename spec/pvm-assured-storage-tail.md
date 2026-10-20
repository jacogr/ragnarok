# Clipped storage reads preserve the full returned length

Pins: GP0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`, storage
read clipping, full returned lengths and regular effects; vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`.

Author FetchReadTail before computation/signing. Fetch the real count and write
[count,22,23]. Read self storage at offset2/request3 into separate zeroed RW+3:
copy only byte23, retaining zero in the two uncopied bytes. Store the full r7
return as eight bytes at RW+6, then persist eleven bytes from RW+3. The independent
oracle is [23,0,0]+LE64(3), distinguishing full length3 from copied count1.
The assured parent contains eleven bytes with byte2=0, while the current regular
write contains three bytes with byte2=23: stale-parent reads would return both
the wrong tail and length11. No memory/response/report/terminal/source patches.

Only this new mode gets original funding58 and capture11 before root/signing/
computation, and shares the bounded32-step policy with read-back. Existing mode
bytes/policies remain unchanged. The guest needs25 instructions/four hosts;
compact exit keeps full code below128 bytes. Original gas10000 then20000 and all
protocol parameters are unchanged. Host costs288+2447+2410+2449=7594, plus one
block at most997: gas>7594and<=8591. Original and next actual gas must be equal.

Completion: actual Halt/Regular, one final key/eleven bytes, footprint46/item1,
balance58/code retained, timestamp3/history3/activity reports2/actual gas/all29
parameters/aliases/finality1 through full composition and publication. Steps25
succeeds/24 refuses; calls2/3 refuse at read/final write. Copy11 succeeds/10
refuses at the final write after the smaller fetch/write/read fit. Final bytes10,
key0 and zero captured-key provenance refuse precisely. Run1000 full successors
with ARC release, affected predecessors, semantic/tooling/inventory/format checks.

Next: read storage after actual deletion and retain the full NONE return.
M1 framing complete; full state serialization, whole-block parity and full
chainspec equivalence remain open.

Observed local evidence: actual original and assured Halt/Regular store the
literal[23,0,0,3,0,0,0,0,0,0,0]. This retains the clipped byte, untouched gap,
and full eight-byte length3. Metadata has footprint46/item1/balance58, with
original code preserved. Both actual gas charges are equal and within the
independent bounds; selected proof has one key/eleven bytes. Full canonical
composition/publication/alias/parameter/finality checks pass.

Steps25 succeeds/24 refuses StepLimitExceeded; calls2/3 refuse
HostCallLimitExceeded. Copy11 succeeds/10 refuses DispatchFailure/LimitExceeded
at the final write. Final bytes10/key0 refuse Completion/Batch/LimitExceeded;
zero captured-key provenance refuses UnsupportedAccountEffects.

One thousand full successors retain754688/754688 occupied bytes. All nine
predecessor groups pass again at1000 cycles: read754224, branch687792,
delete753424, tail753792, ranges938352, list1459632, individual inputs1406672,
original storage2933856 and outcomes3162032 bytes unchanged. Only guest factory,
funding helper and original-execution helper change among3461 predecessor inputs;
3458 are identical. All four affected semantic checks,35 tooling tests, inventory
194 families/2436 probes/274 native suites, and formatting2340 Nim sources plus
Rust pass. Local checked-release macOS evidence; remote CI remains separate.
