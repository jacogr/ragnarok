# Telemetry delivery

[Source guide](../README.md) · [Telemetry contract](../../spec/telemetry.md)

This folder implements the optional bounded JIP-3 telemetry subset and its adapter from actual
peer observations.

| Module | Contents |
| --- | --- |
| [`chain.nim`](chain.nim) | Bounded JIP-4 metadata extraction for telemetry network identity |
| [`wire.nim`](wire.nim) | Owned JIP-3 registration and event encodings |
| [`client.nim`](client.nim) | Nonblocking TCP delivery, bounded queues and reconnect lifecycle |
| [`observer.nim`](observer.nim) | Translation of transport/peer events into copied telemetry observations |

Append `--with-telemetry --telemetry-endpoint HOST:PORT --chain PATH` to a supported proof-peer invocation
with an explicit JIP-4 chain file. Delivery reports local node information, periodic peer/status
observations, handshake outcomes and disconnections. Telemetry is disabled without
`--with-telemetry`; endpoint configuration alone does not enable it.

The chain file identifies the telemetry network; this metadata extraction does not initialize
chain execution or connect bootnodes. [Application services](../app/README.md) own startup and
shutdown, while the observer has no command-line knowledge. Delivery is bounded and driven by
the peer dispatcher rather than a telemetry thread.

The [telemetry contract](../../spec/telemetry.md) records full usage, the implemented event subset,
queue/reconnect behavior and native/E2E checks, including interoperability with the pinned JAM
Tart collector.
