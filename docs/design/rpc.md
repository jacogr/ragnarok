# RPC and chain context

[Design overview](../design.md). Detailed feature contracts live in `spec/`; routine increments
update their feature contract rather than appending progress here.

An optional `src/rpc/` WebSocket JSON-RPC listener shares the existing peer dispatcher. It owns
at most eight nonblocking loopback connections and bounded input/output buffers. The first
method, `ragnarok_clientInfo`, reports implementation and observed runtime metadata. Other chain queries
now expose a genesis-only immutable view when an explicit genesis pair is supplied; subscriptions
remain unavailable until block import and update events exist. `parameters()` reads an immutable
GP 0.8.0 parameter snapshot from the explicit chainspec; four live-state fields are documented zero
placeholders. `src/chain/genesis.nim` retains the configured serialized map through the existing
state store, checks header/roster/time framing, retains the immutable sealed-header codec owner, and computes
its root at startup. It does not validate
all state chapters or run consensus. `src/chain/services.nim` reads account metadata, storage
values, verified preimages and fixed request histories through immutable store views; RPC bounds raw values and aggregate
batch responses before copying them. `src/chain/statistics.nim` validates C(13) against retained
core configuration and current/previous rosters before returning its exact bytes. Genesis capture
also owns a bounded sorted serialized-key index for binary-search pagination; key access returns
fixed copies without exporting state-map storage. It retains sorted IDs from exact valid account entries for bounded `listServices` responses. RPC and telemetry share the same startup file snapshot. See [RPC scope](../../spec/rpc.md).
