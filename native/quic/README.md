# QUIC transport and certificate C bridges

[Native bridges](../README.md) · [Nim networking](../../src/jamnp-s/README.md)

These interfaces adapt pinned QUICHE/BoringSSL operations without moving JAM networking policy
out of Nim.

| Files | Contents |
| --- | --- |
| [`cert_fields.c`](cert_fields.c), [`cert_fields.h`](cert_fields.h) | Complete DER parsing and bounded copied X.509 observations |
| [`transport_bridge.c`](transport_bridge.cc), [`transport_bridge.h`](transport_bridge.h) | Opaque QUIC owners, synchronous callbacks, stream operations and copied connection/admission observations |

Certificate fields are observations; Nim decides peer identity and certificate acceptance.
Likewise, Nim owns UDP readiness, timers, CE framing and application policy. Callback buffers are
borrowed only during the call; enclosing transport owners must remain stable until native
callbacks retire. Teardown precedes destruction of borrowed application owners.

[`build_quic.py`](../../tools/build_quic.py) validates both upstream pins and builds
`libquic_proof` under `build-tools/quic/`. Make provisions checksum-pinned Bazel. Project-owned
embedding rules are appended only to `build-tools/quiche/source`; vendor sources remain pristine.
There are no dependency patches. See [`transport_bridge.cc`](transport_bridge.cc) for scheduling,
authentication, bounded callback turns and handle retirement. JAM protocol logic remains in Nim.

The [networking guide](../../docs/networking.md) records transport setup, certificate fixtures,
feature profiles and verification. [Application download contracts](../../spec/application-download-stream.md)
cover the later native-to-Nim stream retirement and block-input handoffs.

Server connection-handle storage has an explicit startup capacity, bounded by4096 and defaulting
to sixteen. Configuration ends before network processing or peer-observer registration. The
bridge frees its allocation after engine/TLS callbacks retire; Nim retains all membership, role
and admission policy. Explicit multi-peer service applies to both IPv4 and IPv6.

An optional startup admission callback receives the authenticated leaf DER, exact negotiated ALPN,
and prospective free peer slot before native retention. Metadata comes directly from that
session's public TLS stream after mutual authentication. Refusal grants no slot. All role and
reservation decisions remain in Nim. See the [admission contract](../../spec/jamnp-peer-admission.md).

Live peer references copy a process-unique transport identity, admission generation and slot;
no foreign connection pointer leaves C. Targeted stream open/close and stream association validate
all three fields against the current live table. Paired connection/generation arrays are allocated
atomically at startup and freed after engine teardown. See the
[peer-control contract](../../spec/jamnp-peer-control.md).
