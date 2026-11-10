# Checked auxiliary loop

The `pvmAuxLoop` profile qualifies an opt-in adjunct to the shared connected-read JIT.
The [checked loop](../src/pvm/internal/handler_aux_loop.nim) binds the original priced
self-edge and successor. The [native prefix](../src/pvm/internal/native_aux_loop.nim) and
[shared runtime](../src/pvm/internal/native_pipeline.nim) own the staging and image
lifetime contracts. Refusals return to the original checked header for the first
uncommitted visit, preserving Gray Paper execution semantics.

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
