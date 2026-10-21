# QUIC transport and certificate C bridges

[Native bridges](../README.md) · [Nim networking](../../src/quic/README.md)

These interfaces adapt pinned LSQUIC/BoringSSL operations without moving JAM networking policy
out of Nim.

| Files | Contents |
| --- | --- |
| [`cert_fields.c`](cert_fields.c), [`cert_fields.h`](cert_fields.h) | Complete DER parsing and bounded copied X.509 observations |
| [`transport_bridge.c`](transport_bridge.c), [`transport_bridge.h`](transport_bridge.h) | Opaque QUIC owners, synchronous callbacks, stream operations and copied connection/admission observations |

Certificate fields are observations; Nim decides peer identity and certificate acceptance.
Likewise, Nim owns UDP readiness, timers, CE framing and application policy. Callback buffers are
borrowed only during the call; enclosing transport owners must remain stable until native
callbacks retire. Teardown precedes destruction of borrowed application owners.

[`build_quic.py`](../../tools/build_quic.py) validates pinned upstream sources and builds
`libquic_proof` under `build/quic/`, using the maintained public headers. Make owns preparation;
no upstream source patches or separate C implementation of JAM protocol logic are added here.

The [networking guide](../../docs/networking.md) records transport setup, certificate fixtures,
feature profiles and verification. [Application download contracts](../../spec/application-download-stream.md)
cover the later native-to-Nim stream retirement and block-input handoffs.
