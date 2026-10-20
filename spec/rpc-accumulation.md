# Publish finalized accumulation through the RPC dispatcher

## Authority and scope

Use GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Connect the existing state/chain adoption
entry to RPC's same-dispatcher publication and subscription boundary. This changes
no protocol equations, JSON encoding, execution selection or transport ownership.

## Contract and completion tests

`Server.publishAccumulation` accepts the caller's mutable complete-map StateStore,
one opaque finalized execution source and state-only composition limits. A closed
or disabled listener returns Unavailable before inspecting state or source. An open
listener delegates once to applyAccumulationChain using its private selected view.
Every refusal preserves live state, RPC history, finality, sockets, input fragments,
pending reply bytes/offsets and subscription queues, with the actual failed nested
cause and no usable child. No duplicate composition, capture or append is added.

After complete success, both live handles own the exact accepted posterior before
queuing best-head updates through the same helper as publishBlock. Return the exact
installed child. Existing subscribers receive updates from that snapshot; old
request contexts retain their previous immutable view. Preserve reply-before-event
ordering, partial-input deadlines and independently selected finality. FIFO overflow
closes only the overflowing consumer after successful adoption and never rolls back
accepted state or other clients. No socket writes occur during publication.

Test genuine signed successors with best/statistics/finalized subscriptions and
connected nonblocking local sockets. Check exact head/state identity and independent
adoption parity, one-pass hashing, late capture/append refusal without events,
retry/replay, queued reply suffixes and next-tick reads. Test disabled/closed/missing
view lifecycle, subscribed/unsubscribed/not-upgraded/closing slots, consumer overflow
isolation, detached outputs and repeated publication/refusal/close ARC release.
Add strict selected-result access guards, privacy and finalized-source compiler guards.
Run the existing RPC consumer suite and source-owned inventory/tooling checks.

## Remaining work

This is an explicit in-process handoff on one dispatcher thread. It does not create
a live network block importer, scheduling policy, fork choice, full block validity,
complete execution-configuration validation, verified finality or persistent commit.
The next integration must supply finalized sources from an application-owned import
path while retaining operation when optional RPC is disabled. Execution/finalization
remains PVM-owned. M1 framing is complete; full state serialization and JAM/STF parity
remain open.

## Observed local verification

`make unit SUITE=rpc_accumulation` passes on pinned Nimony/ARC with checked
optimized contracts and Clang LTO. Genuine signed empty, combined incoming/
available/lookup/provide, dispute, ticket and epoch-crossing successors reach the
server's existing wire and queue logic. Posterior statistics notifications remain
readable. State, selected head and returned child share one exact snapshot; hash
work equals independent state/chain adoption without repeated composition/capture.

Real nonblocking socket pairs verify queued reply suffixes precede best/statistics
updates, partial input survives without deadline extension, and later requests see
the new head. Finality changes only when explicitly published. Default/disabled/
closed listeners, missing view, invalid source, late consensus limits, capture hash
failure and NotChild refusal retain state and pending messages; retry succeeds and
replay queues nothing. FIFO overflow closes only its consumer; unsubscribed,
unupgraded and closing slots receive no events. One thousand publication/replay/
close/refusal cycles release native endpoints and retain 458,992 occupied bytes
before and after.

The existing `rpc` suite passes with its original crypto-only link profile. Three
strict runtime extraction probes, three compiler privacy rejections and one
finalized-source domain rejection pass. All 33 targeted verification and
failure-harness tooling tests, source-owned inventory, pinned Nim/Rust formatting
and Git whitespace checks pass. Logs are under `build/rpc-accumulation*`, with
native output under `build/tests/native/selected/`. Exact-head Linux CI and full
JAM/STF parity remain separate evidence.
