# Accumulation general-host dispatch

This bounded increment follows Gray Paper 0.8.0, pinned at
`07f041dabd073f9018b418e9ee72e79dd2185401`, `pvm_invocations.tex`:
Psi_A's dispatcher F and the general/refine/accumulate host identifier tables.

`executeAccumulationMachine` captures fetch sources from the supplied prepared
machine's own bootstrap, then executes that same immutable initial CPU. Parameters
and local limits are explicit. Gas (0) and fetch (2) use the existing host
implementations. Known accumulation calls 1, 3–6 and 15–27 are local
`UnsupportedHostCall` failures, even when their eventual protocol implementation
might exhaust gas. Refine-only calls 7–14 and all other identifiers use F's unknown
branch: charge 1000 and set r7 to WHAT, including on gas exhaustion. IDs are compared
at their complete uint64 width.

Capture, copying, instruction count, host-call count and gas-analysis budgets stay
separate. Local failures expose no machine or execution progress. Completed guest
outcomes retain the engine's snapshot, including terminal gas deficit. Repeated
calls start from the unchanged initial CPU; there is no stateful resume facility.

Completion tests cover every unavailable and refine-only identifier, unknown
boundary IDs, funded and exhausted gas/fetch/unknown calls, exact return registers,
engine budget refusals, preparation refusal, repeatability, result privacy and
failed-access contracts, and ARC release. These are authored adapter witnesses;
existing primitive tests retain detailed fetch memory and gas boundary coverage.

This is not complete Psi_A: grow_heap, account reads/writes, accumulation effects,
checkpoint rollback, result normalization and state publication remain absent.
The existing signed gas-domain gate remains open. Next bounded work is grow_heap
semantics and memory-boundary tests before adding it to this dispatcher.
