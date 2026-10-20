# Apply a finalized accumulation successor

## Scope and authority

Use GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401` and
vectors `d3c089c9a1d5352ad353626d7a2db8589f137b2a`. This increment connects the
existing [state composition](accumulation-completion.md) and
[exact-parent publication](accumulation-block-publication.md) contracts. It changes
no equations, encoding, upstream pins, execution selection or effect certificates.

## Contract

`applyAccumulationState` accepts a mutable complete-map StateStore, one opaque
PreparedFinalAccumulation and existing state-only AccumulationCompositionLimits.
PVM owns that finalized successor; this entry never executes/finalizes guests.
Reject an invalid source first, then an uninitialized target, then a target that
does not retain the exact original parent. These preflight checks perform no
hashing. Equal-root reconstructed maps, restored versions, execution-stage maps,
foreign parents and already published handles cannot substitute for that parent.

Compose through the sole prepareAccumulationComposition implementation. Preserve
its exact failed phase and nested reason; intermediate owners stay private. On
success, delegate to publishAccumulationState, which rechecks parent identity and
performs the sole caller-handle replacement. Return the exact published snapshot;
old handle aliases, snapshots, views and the finalized source remain unchanged.
Caller limits cannot replace the source's inherited store policies. Separate
parent handles may independently apply the same successor; replay on an updated
handle refuses before composition. Every refusal leaves the target unchanged.

Defaults/refusals carry only reasons. Composition/publication failure accessors
are available only for their selected failed alternative. Do not accept raw
snapshots, stopped histories or detached maps as finalized execution authority.
This remains single-threaded in-memory full-state application, with no persistent
commit, wall-clock admission, full-block validity or light-state claim.

## Completion tests

Require genuine signed empty/incoming/available/provided/dispute/ticket/epoch
successors; full-map parity with the existing independently prepared state chain;
exact returned/caller identity and literal target-time bytes. Compare hash work
with one composition pass. Test source/target/default precedence, equal-root and
restored-version rejection, wrong execution-stage state, stale replay and
independent parent branches with hashing unavailable during preflight. Exercise
every short composition phase policy, nested reasons, inherited late write limits,
early/late hash failure and successful retry, preserving target/source owners.
Retain detached snapshots/views and measure 1,000 success/refusal ARC cycles.
Add strict extraction guards and compiler privacy/source-domain rejections.

## Remaining work

The execution-side entry that joins initial execution, bounded driving and
finalization remains execution-owned. This entry consumes its finalized owner.
Full block admission/validity, persistence and JAM/STF parity remain open.
M1 framing remains complete; full state serialization remains open.

## Observed local verification

On macOS with pinned Nimony/ARC, Clang LTO and checked bounds/contracts,
`make unit SUITE=accumulation_state` passed. Genuine signed empty, incoming,
combined available/lookup/provide, dispute, ticket and epoch-crossing sources
match independently constructed complete-map roots and every original entry.
Returned/caller snapshot identity, literal times, historical aliases/views and
independent parent branches retain their expected behavior. Hash work equals
one direct composition pass; stale/default/wrong-parent preflight hashes nothing.

All nine short phase policies preserve their original failed phase and the
caller's exact parent. Inherited six-write policy refuses the final seven-write
consensus overlay. Early and final-hash backend failures preserve the target,
retain the precise late consensus BackendFailure, and permit successful retry.
Detached output snapshots outlive all source and target handles. One thousand
success/stale-replay/late-policy-refusal ARC cycles retain 1,196,640 occupied bytes
before and after.

Five strict runtime extraction guards, four compiler privacy rejections and three
finalized-source domain rejections pass. All 33 targeted verification-inventory,
profile and failure-harness tooling tests pass, along with source-owned inventory,
pinned Nim/Rust formatting, local feature links and Git whitespace checks.
Existing PVM, composition and publication implementations and shared fixtures
are unchanged; their merged verification remains applicable. Logs remain under
`build/accumulation-state/`, with native execution output in
`build/tests/native/selected/accumulation_state.log`. Exact-head Linux CI and full
JAM/STF parity remain separate evidence.

Next state integration connects the caller's block-application path to this
entry. Admission/validity and execution/finalization keep their existing owners.
