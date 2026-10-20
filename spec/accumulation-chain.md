# Adopt accumulation state and chain history together

## Authority and scope

Use GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. This increment composes existing state
application, structural chain capture and direct-child view advancement. It changes no
protocol equations or execution/effect selection. PVM supplies PreparedFinalAccumulation.

## Contract and completion tests

`applyAccumulationChain` accepts mutable StateStore and ChainView handles, an opaque
finalized source and state-only composition limits. Refuse invalid source, missing target,
stale target, missing view and stale view in that order. Both target and selected head
must retain the source's exact original parent; equal roots are insufficient. Compare
retained admission core/epoch/author-population domains with the selected head before work.
These preflight checks hash nothing. Extract chain parameters from the selected head,
never from a caller replacement; the caller still owns consistency of the complete execution
configuration with those parameters.

Apply on a private state handle through applyAccumulationState. Serialize only the source's
admitted sealed header under the existing 256 KiB chain cap, capture its exact posterior
snapshot, and call advanceView. Preserve each actual failed phase reason without exposing
partial state, header bytes or history. Only full success replaces both caller handles and
returns the exact child installed in the view. No fallible work or callbacks occur between
those final assignments. This is single-threaded in-memory atomicity, not durability or
concurrent synchronization. Existing aliases, retained views and explicit finality survive.

Test signed empty, incoming/available/lookup/provide, dispute, ticket and epoch successors;
independent apply/capture/append parity and one composition plus one header hash; exact
live-state/head identity, parent lookup, preserved finality and detached ownership. Test
hash-free default/stale/root-equal/profile preflight, early/late composition failures,
late capture hashing failure, late NotChild refusal, retry and independent branches.
Measure 1,000 success/replay/late-refusal ARC cycles. Add strict selected-accessor guards,
private-result compiler rejections and finalized-source domain rejection.

## Remaining work

Full block validity/admission, complete execution-configuration consistency, fork choice,
consensus finality verification, persistence and JAM/STF parity remain open. This entry does
not execute/finalize guests or send RPC notifications. Next integrate the completed pair
with the dispatcher's existing publication/notification boundary without exposing a split
state/head update. M1 framing is complete; full state serialization remains open.

## Observed local verification

`make unit SUITE=accumulation_chain` passes on pinned Nimony/ARC, Clang LTO and
checked optimized contracts. Genuine signed empty, incoming, combined available/
lookup/provide, dispute, ticket and epoch-crossing sources match independently
spelled apply/capture/append results for every posterior entry, root and block
identity. Hash work equals one state application plus one sealed-header hash.
Both live handles and the returned child share the exact posterior map; original
aliases, parent lookup, explicit finality and detached returned owners survive.

Default/stale/equal-root/profile preflight performs no hashes. Early and final
composition hashing failure, inherited late write limits, late header-hash
failure and NotChild append refusal preserve both caller handles. Backend and
append refusals permit retry with the same finalized source.
One thousand success/replay/late-append-refusal cycles retain 724,368 occupied bytes
before and after.

Eight strict runtime extraction probes, three compiler privacy rejections and
one finalized-source domain rejection pass. All 33 targeted verification and
failure-harness tooling tests, source-owned inventory, pinned Nim/Rust formatting
and Git whitespace checks pass. Existing application/capture/provider behavior is
unchanged and its earlier local consumer evidence remains applicable. Logs are
under `build/accumulation-chain*`; native output is under
`build/tests/native/selected/accumulation_chain.log`. Exact-head Linux CI and
full JAM/STF parity remain separate evidence.
