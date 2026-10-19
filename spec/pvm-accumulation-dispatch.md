# Accumulation general-host dispatch

This bounded increment follows Gray Paper 0.8.0, pinned at
`07f041dabd073f9018b418e9ee72e79dd2185401`, `pvm_invocations.tex`:
Psi_A's dispatcher F and the general/refine/accumulate host identifier tables.

`executeAccumulationMachine` captures fetch sources from the supplied prepared
machine's own bootstrap, prepares initial I using the explicit `AccumulationContextConfig`,
then executes that same immutable initial CPU. Mandatory C(2)/C(7)/C(12) chapters must
exist and match the configured profile; the adapter never accepts substitute effects. Parameters
and local limits are explicit. Gas (0) and fetch (2) use the existing host
implementations; [lookup (3)](pvm-accumulation-lookup.md) reads account preimages
through bounded immutable state-value slices. Checkpoint (18), yield (26) and [provide (27)](pvm-accumulation-provide.md)
retain versioned implication effects.
Known accumulation calls 1, 4–6, 15–17 and 19–25 are local
`UnsupportedHostCall` failures, even when their eventual protocol implementation
might exhaust gas. Refine-only calls 7–14 and all other identifiers use F's unknown
branch: charge 1000 and set r7 to WHAT, including on gas exhaustion. IDs are compared
at their complete uint64 width.

Capture, copying, provision retention, instruction count, host-call count and
gas-analysis budgets stay separate. Local failures expose no machine or execution progress. Completed guest
outcomes retain the engine's snapshot, including terminal gas deficit, and both
implication dimensions through the guarded `effects` accessor. Repeated
calls start from the unchanged initial CPU; there is no stateful resume facility.

Completion tests cover every unavailable and refine-only identifier, unknown
boundary IDs, funded and exhausted gas/fetch/unknown calls, exact return registers,
engine budget refusals, preparation refusal, repeatability, result privacy and
failed-access contracts, and ARC release. These are authored adapter witnesses;
existing primitive tests retain detailed fetch memory and gas boundary coverage.

## Checkpoint and yield host behavior

The same pinned `text/pvm_invocations.tex` defines Omega_C (18) and Omega_Taurus (26).
`text/definitions.tex` pins their base costs at 103 and 98. The general-functions
preamble charges before table-specific changes: underfunding returns exact terminal
gas deficit and preserves registers, memory and both dimensions. These are general
host costs, separate from the engine's prepaid instruction-block cost.

A funded checkpoint retains X as Y and returns remaining gas in r7. A funded yield
reads exactly 32 bytes at the full uint64 r7 pointer using the existing bounded,
nonwrapping host memory operation. Success replaces only X's yield and returns OK
(0); an all-zero hash is present. Unreadable or out-of-address-space intervals panic
after charging, preserving r7 and both dimensions. Local copy-limit exhaustion
refuses without exposing CPU state or effects. Checkpoint does not need copy credit.
No host call changes memory or unrelated registers.

Each execution initializes its private effects from that exact machine bootstrap.
Later local host/engine refusal discards all private versions; a completed guest
panic, fault or OOG retains both dimensions for later outcome normalization. There
is no caller-selected replacement state, implicit checkpoint on yield, mutation of
previous results or persistent state publication.

Completion witnesses use actual decoded guest programs for exact/insufficient gas,
post-charge r7, unchanged registers, RO/RW/cross-page reads, absent versus zero yield,
yield/checkpoint/re-yield history, charged failed reads, full-width pointers,
trapping after yield, policy refusal after earlier effects, repeatability and
1,000 ARC release cycles. Privacy and runtime probes cover the effects accessor.
These are authored equation witnesses, not published complete Psi_A vectors.

Remaining work includes grow_heap's documented semantic decision, other account and
accumulation calls, terminal regular/exceptional selection, result normalization and
state publication. The existing signed gas-domain gate remains open.
[Terminal normalization](pvm-accumulation-outcome.md) now selects the retained
regular/exceptional effects, applies the halt-return rule and caps gas usage.
Remaining host calls and persistent publication are subsequent work.


## Local verification (2026-10-19)

Pinned Nimony/ARC/checked Clang LTO verification passed for native
`pvm_accumulation_dispatch`, `pvm_accumulation_machine` and
`pvm_accumulation_fetch` through the existing `native_tests.run_units` scheduler.
The dispatcher retained 676,880 occupied bytes before and after 1,000 execution/
release cycles. Both shared-fixture consumers also passed their own ARC witnesses.
The existing `failure_checks.run_failure_suite` passed all five dispatch result
probes, and `test_guards.compile_rejections` passed both dispatch privacy probes.
Nine selected Python tests cover verification inventories, guard registration and
failure-family registration. `tools/check_inventory.py`, pinned Nim/Rust formatting
and `git diff --check` passed. A mistyped Python discovery pattern initially found
zero tests; that is not counted as verification and the correct inventory suite
was subsequently executed successfully.

Full evidence remains under `build/pvm-yield/`, including `native-final.log`,
`verification.log`, `targeted-results.json`, the selected Python logs and
`format-check.log`. Initial native compilation caught untyped arithmetic literals
in the new pointer witnesses; explicit uint64 literals corrected the tests.
The final dispatcher suite was rerun after the last executable test change.
The verified pinned tool installation was reused from the sibling checkout;
crypto/observer dependencies were rebuilt locally. Only affected checks ran;
complete six-group verification and Linux CI are not claimed.
