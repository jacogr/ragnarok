# WebSocket JSON-RPC

[Source guide](../README.md) · [RPC and chain design](../../docs/design/rpc.md)

This folder exposes bounded JSON-RPC queries and subscriptions over immutable configured chain
views. It implements part of JIP-2 plus documented diagnostic/state extensions.

| Module | Contents |
| --- | --- |
| [`protocol.nim`](protocol.nim) | JSON-RPC parsing, dispatch, response bounds and configured chain/service queries |
| [`wire.nim`](wire.nim) | HTTP upgrade, RFC 6455 framing, UTF-8 validation and incremental frame decoding |
| [`wire_stream.nim`](wire_stream.nim) | Task-owned Nimony Reader and Writer with bounded byte handoff |
| [`server.nim`](server.nim) | Optional loopback listener, bounded connections/subscriptions, publication and detached dispatcher entry points |
| [`transport_bridge.nim`](transport_bridge.nim) | Bounded detached-byte mailboxes with generation and in-flight output credit |
| [`websocket_transport.nim`](websocket_transport.nim) | Stock split-half IO tasks and RPC-specific upgrade admission |

Append `--with-rpc` to a supported proof-peer invocation to expose `ws://127.0.0.1:9418/`;
`--rpc-port NUMBER` changes the port. RPC is disabled unless `--with-rpc` or `--with-ui` is
specified. `ragnarok_clientInfo` exposes the same build identity as the executable's `--version`.
`--chain PATH` supplies protocol parameters and can seed a configured genesis view when it
contains an explicit header/state pair.

[Chain modules](../chain/README.md) retain query snapshots. [Application services](../app/README.md)
own startup and coordinate selected state with explicit dispatcher publication. Subscriptions
observe supplied history and caller-certified finality; RPC supplies no consensus or finality
algorithm. Missing-state behavior and configuration-derived placeholders are explicit.

See the [RPC contract](../../spec/rpc.md) for the method surface, bounds, subscription lifetimes,
publication rules and native/E2E verification.
