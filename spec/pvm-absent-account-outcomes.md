# Absent-account accumulation outcomes

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
eq:accinvocation first branch. The local basestate macro is ao-poststate, so the
absent-account result retains the exact input state. No incoming credit occurs,
no code is resolved or executed, and gas used, modified accounts, outgoing
transfers, provisions and yield are zero/empty. Incoming amount sums, including
values that would overflow an account pool, are irrelevant to this branch.

Construct a distinct immutable absent-account certificate from genuine prepared
inputs, the selected full-width invocation ordinal, an initialized complete source
snapshot and explicit slot. Only actual metadata absence succeeds. Present records,
including malformed present metadata, refuse this certificate and must follow the
normal service preparation/validation path. No default PreparedAccumulationService,
SkippedAccumulation or executed AccumulationOutcome is fabricated.

Retain exact input/index/state ownership and copy fixed observations through guarded
accessors. This constant-work factory allocates no input-derived arrays or payloads;
input preparation already proves input counts and gas domains. A separate initial
block adapter derives inputs, admitted-parent snapshot and authenticated slot from
a genuine block round, retaining that round alongside the pure projection.

Tests must prove no credit/arithmetic/hash work for extreme liquid/protected inputs,
exact identity and zero effects, present/default/index/state refusal, retained source
lifetime, signed block authority, private/nominal/executed-domain guards and ARC.
This certificate is separate from current legacy batch and runner publication;
complete missing-account coverage and statistics integration remain required.

The new suite and the existing code-unavailable skip suite pass with fresh
1,000-cycle ARC evidence. Pure witnesses cover absent service IDs 0,99 and
MAX-u32, MAX-u32/zero slots, MAX-u64 offered gas and repeated MAX-u64 incoming
amounts to either pool. Nonzero source ordinals, initialized empty input owners,
malformed present metadata, source lifetime and typed refusal are covered.
A genuinely signed admitted block selects unknown service99 by its sole allowance;
the bound proof retains the actual parent, round and slot without code execution.

All 273 production modules,8 strict runtime extraction guards,5 compiler
privacy/nominal/executed-domain checks and54 focused harness tests pass. Inventory,
canonical formatting and diff checks pass. Evidence remains under
`build/absent-account-outcomes-*` and
`build/tests/absent-account-outcomes-*`; checked macOS ARC/Clang observations
remain separate from Linux CI and current-round publication integration.

Next: certify exact input coverage across original executions, code-unavailable
skips and absent-account outcomes, retaining actual gas even after annulment.
