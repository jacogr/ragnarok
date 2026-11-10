# Checked auxiliary loop

The `pvmAuxLoop` profile is an opt-in adjunct to the shared connected-read JIT. The cold
checked branch resolver can nominate a complete 15-operation byte-store loop with an exact
priced self-edge and a distinct original successor. A stream retains its first structural
match and performs at most eight full cold probes per epoch. The warmed primary must make
progress alongside 274 checked self-edges in one settled segment before an optional image
can be requested. The ordinary dispatch loop does not consult an auxiliary proof.

ARM64 and Linux x86-64 emit the same eleven-operation checked read prefix. The shared bridge
stages the store operands and scalar suffix. A complete visit commits through the original
byte-store worker only when the current contiguous writable extent and both dirty
representations agree. A verified page is retained for at most 256 visits in one exclusive,
callback-free borrow. A read refusal, first write, insufficient gas, or partial reservation
returns to the original checked header for the first uncommitted visit.

The runtime requires two free image credits before reserving the optional image. Primary work
has priority on the existing single compiler and can revoke the optional mapping. A running
borrow delays physical retirement only to its bounded return. Credit reuse follows physical
unmapping, including on invalidation and close.

On native Linux ARM64, run `make unit SUITE=pvm_aux_loop_arm`. On native Linux x86-64,
run `make unit SUITE=pvm_aux_loop_x86`. The same source fixtures exercise relocated
native loops, changed operands, checked refusal and committed-prefix parity, ownership,
priority, cancellation, retirement, and close. The matching native unit suite must execute
on both ISAs before promotion.

For the prepared DOOM tick check, compile the maintained driver with the matching native JIT,
`pvmAuxLoop` and `pvmArm64JitOwnerReceipt`, and set `RAGNAROK_PVM_DOOM_AUX=1` together
with the standard prepared JIT environment and frozen tick fixtures. The untimed driver allows
up to eight warmup invocations. It waits for admitted compiler work at the boundary with a
five-second deadline, then checks the parked auxiliary before each of the eleven warm invocations.
It validates terminal state, gas, complete memory, source immutability, and host events before
reporting `AUX_LOOP_RESIDENT,11` and the incumbent renderer's warm-work delta.
