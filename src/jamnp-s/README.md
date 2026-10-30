# JAMNP-S protocol and peer dispatch

[Source guide](../README.md) · [Networking guide](../../docs/networking.md)

This folder owns JAMNP-S identity, stream policy and bounded peer scheduling over the maintained
[LSQUIC C bridge](../../native/quic/README.md). Peer identity, protocol framing and application
adoption remain explicit Nim decisions.

| Modules | Responsibility |
| --- | --- |
| [`messages.nim`](messages.nim), [`audits.nim`](audits.nim) | Bounded generic E4 messages and upgraded CE144/145 structural batch codecs |
| [`protocol.nim`](protocol.nim) | Pinned JAMNP-S peer identity, names and CE framing checks |
| [`../quic/io.nim`](../quic/io.nim), [`../quic/transport.nim`](../quic/transport.nim) | Underlying POSIX readiness/UDP dispatch and native transport callbacks |
| [`session.nim`](session.nim) | Retained peer/mesh sessions and private stream owners |
| [`integration.nim`](integration.nim) | CE 143 proof workloads over complete C.2 digest captures |
| [`offload.nim`](offload.nim) | Fixed two-worker proof queue with owned inputs, bounded capacity and explicit completion/cancellation |
| `ancestor/stream.nim`, `ancestor/peer.nim` | Bounded descending CE 128 context, explicit TLS pins and stream/connection retirement before header decoding |
| `block/download/`, `current/block/download/` | CE 128 stream reception, pinned outgoing peers, attempt/session ownership and the one-child download dispatcher |

Callbacks borrow stable owners only during the documented lifetime; teardown retires callbacks
before descriptors and enclosing services disappear. Block reception, private preparation and
deferred adoption run as separate stages. Networking does not infer execution or finality from
successful authentication or receipt of bytes.

The [networking guide](../../docs/networking.md) covers commands, certificates, fixtures and
verification. The [download-stream](../../spec/application-download-stream.md) and
[download-loop](../../spec/application-download-loop.md) contracts describe application handoffs;
[application services](../app/README.md) own optional RPC, UI, telemetry and canonical state.

The child download dispatcher can pause for certified missing report context after
worker collection and graceful peer connection retirement. Resumption preserves
the original attempt, prepared block and deadline; successive children reconnect
only the same configured pins. See [the on-demand contract](../../spec/state-ancestor-context.md).

The [compliance inventory](../../spec/jamnp-compliance.md) records the pinned requirements and
remaining runtime gaps. Moving these modules does not add stream support.
