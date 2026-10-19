# RPC and chain context

[Design overview](../design.md). Detailed feature contracts live in `spec/`; routine increments
update their feature contract rather than appending progress here.

An optional `src/rpc/` WebSocket JSON-RPC listener shares the existing peer dispatcher. It owns
at most eight nonblocking loopback connections and bounded input/output buffers. The first
method, `ragnarok_clientInfo`, reports implementation and observed runtime metadata. Other chain queries
start with a genesis-only immutable view when an explicit genesis pair is supplied. Best-block
subscriptions receive that initial descriptor and subsequent dispatcher publications. `parameters()` reads an immutable
GP 0.8.0 parameter snapshot from the explicit chainspec and the retained active validator count
when genesis is present. Optional complete C(4) decoding at capture supplies a cached ticket-attempt
limit from the pending roster; queries do no Safrole decoding. Active C(8) also supplies cached
erasure piece geometry. Missing state retains documented zero placeholders.
`src/chain/genesis.nim` retains the configured serialized map through the existing state store, checks header/roster/time framing, retains the immutable sealed-header codec owner, and computes
its root at startup. It does not validate
all state chapters or run consensus. `src/chain/services.nim` reads account metadata, storage
values, verified preimages and fixed request histories through immutable store views; RPC bounds raw values and aggregate
batch responses before copying them. `src/chain/statistics.nim` validates C(13) against retained
core configuration and current/previous rosters before returning its exact bytes. Genesis capture
also owns a bounded sorted serialized-key index for binary-search pagination; key access returns
fixed copies without exporting state-map storage. It retains sorted IDs from exact valid account entries for bounded `listServices` responses. RPC and telemetry share the same startup file snapshot. See [RPC scope](../../spec/rpc.md).

`src/chain/provider.nim` owns the immutable `ChainView` boundary for best-block selection,
exact hash/parent lookup and bounded retained-report lookup. The startup adapter seeds the
view with configured genesis; `advanceView` creates a new history of at most eight direct-child
snapshots after parent-hash, slot, prior-root and full parameter-tuple checks. Result payloads
retain their own ARC lifetime. RPC receives
one copied view per dispatcher tick, shared by that tick’s request contexts and batch members.
Replacing a separate view handle cannot alter an existing context. JSON/Base64 handling remains
in RPC; typed hashes cross the provider boundary. Startup configuration and wire behavior are
unchanged. `BlockSnapshot` generalizes the existing owner while preserving the `Genesis` aliases
and startup capture wrapper. Each successful append uses a fresh private sequence and evicts the
oldest snapshot when full; existing readers continue to own their previous snapshots. Retention
is bounded per view, not across arbitrarily many caller-held views. The server exposes `publishBlock`
for same-dispatcher handoff between ticks; it installs a successful append without changing queued replies or transport ownership. Future validated block-import
integration must call this boundary; no live importer, fork choice or consensus finality verification is provided here. Retained-report lookup still searches only the selected head.

`finalizeView` records caller-certified finality for a known retained chain block, refusing regressions.
`publishFinalized` installs that immutable selection between dispatcher ticks. One additional snapshot
owner preserves finalized-state lookup after rolling-history eviction. Neither genesis nor best-head
publication establishes finality; the consensus source must explicitly supply it. `finalizedBlock()`
and client information read this selection, while finalized subscription routing remains separate.

Each WS connection owns a private `RpcSession` with a fixed subscription table and bounded FIFO
of serialized best-block, statistics, service-data, service-value, service-preimage and service-request notifications, limited by message count and bytes. Request dispatch commits subscription changes only when
its reply fits the response budget. Publication queues descriptors and validated C(13) bytes without retaining snapshot owners;
overflow closes only the affected connection. The dispatcher writes replies before notifications,
one frame per turn, preserving partial-write offsets. Statistics are decoded once per connection
per publication when requested. Service-data subscribers retain a nominal service selector and read
one validated fixed account record per update. Service-value subscribers also own a bounded immutable
key and read a bounded storage value; absence remains a successful null, distinct from present empty bytes. Invalid values
terminate only affected subscriptions with an error. Preimage selectors retain fixed nominal hashes
and reuse bounded reads plus content-hash verification. Request selectors add a nominal length
and return fixed validated histories through the same slot-array serializer as queries.
Disconnect releases the entire session.
