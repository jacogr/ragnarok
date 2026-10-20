# Application-owned state and selected history

## Authority and scope

Use GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Add a private canonical application
state/history owner consuming the existing opaque finalized successor. This changes
no protocol equations, execution selection, CLI flags or service startup behavior.

## Contract and completion tests

`initApplicationChain` requires an explicitly initialized ChainView and forks its
head's exact complete-map snapshot, inheriting its resource policy. It performs no
hashing or raw-map rebuilding. Default owners have no state/head. Read-only getters
retain immutable state/history; copied application handles form independent branches.
No field exposes a mutable store or independently replaceable view.

The RPC-independent `applyAccumulation` delegates once to applyAccumulationChain,
so complete state adoption works without a listener. The explicit RPC overload
joins state, application history and listener history before notification work.
Require sameChainView: matching nonempty ordered retained block identities, exact
state owners, complete parameter tuples and explicit finality. Best-root equality
alone is insufficient. Closed or divergent listeners refuse without fallback or
hashing. Source/configuration checks, private composition, capture and direct-child
append keep their existing owners. Every refusal preserves canonical state/history
and pending notifications; success returns the exact installed child.

Test genuine signed empty/incoming/available/lookup/provide/dispute/ticket/epoch
sources, direct adoption parity and one-pass hashing, no-RPC operation, exact owner
identity, independent copied branches, inherited readonly/late policies, detached
outputs and default/accessor failures. Use public application/RPC APIs and real
loopback WebSocket requests to verify joined publication, next-tick reads, replay,
late hash refusal/retry, unavailable listener behavior, retained-window/profile/
root-equal/finality mismatch preflight and unchanged queued events. Check identical
and default view comparison without hashing. Measure 1,000 successful/refused
application owner lifetimes. Add runtime extraction, privacy and source-domain
compiler probes; run affected RPC suites and registry/tooling checks.

## Remaining work

This supplies the canonical application handoff API, not a live network importer,
execution scheduler, full validity/fork-choice/finality verification or persistent
commit. Startup must still provision a writable complete-state seed explicitly;
this constructor preserves the existing raw genesis adapter's zero-write policy.
A later application integration must connect source production and lifecycle to
this owner without making optional RPC necessary. PVM retains execution/finalization.
M1 framing is complete; full state serialization and JAM/STF parity remain open.

## Observed local verification

`make unit SUITE=application_chain` passes on pinned Nimony/ARC with checked
optimized contracts and Clang LTO. Signed empty, combined incoming/available/
lookup/provide, dispute, ticket and epoch-crossing sources match direct adoption.
Initialization/comparison hashes nothing; both direct and RPC paths use one state/
chain pass. Copied owners retain independent branches, old state and explicit
finality. Raw-capture readonly policy and inherited late six-write refusal remain
intact; detached children outlive their source/application handles.

Public RPC/application APIs with a real ephemeral loopback WebSocket client verify
joined publication, exact installed map identity, accepted-head notifications and
later queries. Different finality and an independently shortened retained history
refuse before hashing. Late capture hashing failure preserves the old head and
queues no event ahead of an old-head reply; retry succeeds and replay refuses.
Closed listeners do not trigger fallback; direct adoption still works without RPC.
Equal-root reconstructed maps and non-framing parameter changes fail exact-view
comparison. One thousand success/replay/late-quota-refusal cycles retain 551,712
occupied bytes before and after.

Five strict runtime probes, five compiler privacy rejections and one application
source-domain rejection pass. The existing RPC publication suite and its source-
domain compiler guard pass with the new overload. All 33 targeted verification/
failure-harness tooling tests, source-owned inventory, pinned Nim/Rust formatting,
the new local design link and Git whitespace checks pass. Logs are under
`build/application-chain*`, with native output under `build/tests/native/selected/`.
Exact-head Linux CI and full JAM/STF parity remain separate evidence.

### Structured JSON writer integration

The complete five-layer stack is rebased onto merged
[PR #257](https://github.com/jacogr/ragnarok/pull/257), master commit
`3fc89044d8f7ba1bac4ee1b4be70847892620399`. Git range-diff confirms all five
implementation patches are unchanged. Publication continues to use the protocol
layer's structured writer; no separate JSON output path was introduced.

On that base, `make unit SUITE=rpc`, `make unit SUITE=rpc_accumulation` and
`make unit SUITE=application_chain` pass, including writer regression checks,
subscriber output, late-refusal/retry and public WebSocket handoff. The two
1,000-cycle suites retain 458,992 and 551,232 occupied bytes respectively before
and after. Pinned formatting passes. Logs use `build/application-chain-257-*`.
