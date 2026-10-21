# QUIC networking and peer dispatch

[Source guide](../README.md) · [Networking guide](../../docs/networking.md)

This folder owns Nim networking policy and bounded nonblocking scheduling over the maintained
[LSQUIC C bridge](../../native/quic/README.md). Peer identity, protocol framing and application
adoption remain explicit Nim decisions.

| Modules | Responsibility |
| --- | --- |
| [`protocol.nim`](protocol.nim) | Pinned JAMNP-S peer identity, names and CE framing checks |
| [`io.nim`](io.nim), [`transport.nim`](transport.nim) | POSIX readiness/UDP dispatch, transport callbacks and deadlines |
| [`session.nim`](session.nim) | Retained peer/mesh sessions and private stream owners |
| [`integration.nim`](integration.nim) | CE 143 proof workloads over complete C.2 digest captures |
| [`offload.nim`](offload.nim) | Fixed two-worker proof queue with owned inputs, bounded capacity and explicit completion/cancellation |
| `block_download_*` | CE 128 stream reception, pinned outgoing peers, attempt/session ownership and the one-child download dispatcher |

Callbacks borrow stable owners only during the documented lifetime; teardown retires callbacks
before descriptors and enclosing services disappear. Block reception, private preparation and
deferred adoption run as separate stages. Networking does not infer execution or finality from
successful authentication or receipt of bytes.

The [networking guide](../../docs/networking.md) covers commands, certificates, fixtures and
verification. The [download-stream](../../spec/application-download-stream.md) and
[download-loop](../../spec/application-download-loop.md) contracts describe application handoffs;
[application services](../app/README.md) own optional RPC, UI, telemetry and canonical state.
