# QUIC transport and certificate C bridges

[Native bridges](../README.md) · [Nim networking](../../src/jamnp-s/README.md)

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
`libquic_proof` under `build-tools/quic/`, using the maintained public headers. Make owns preparation;
the vendor inputs remain pristine. An explicitly approved, hash-bound public stream-reset API
patch is applied only to a build-directory LSQUIC copy. The bridge imports the patched public
header, with no private LSQUIC entry points. See [the feature contract](../../spec/jamnp-block-service.md)
for upstream checks, provenance and rejection tests. JAM protocol logic remains in Nim.

The [networking guide](../../docs/networking.md) records transport setup, certificate fixtures,
feature profiles and verification. [Application download contracts](../../spec/application-download-stream.md)
cover the later native-to-Nim stream retirement and block-input handoffs.

Server connection-handle storage has an explicit startup capacity, bounded by4096 and defaulting
to sixteen. Configuration ends before network processing or peer-observer registration. The
bridge frees its allocation after engine/TLS callbacks retire; Nim retains all membership, role
and admission policy. Explicit multi-peer service applies to both IPv4 and IPv6.

An optional startup admission callback receives the authenticated leaf DER, exact negotiated ALPN,
and prospective free peer slot before native retention. Correlation uses a bounded live-SSL registry
and public `lsquic_ssl_to_conn`; SSL ex-data destruction retires entries before registry free.
Refusal grants no slot. All role/reservation decisions remain in Nim. See the
[admission contract](../../spec/jamnp-peer-admission.md).

Live peer references copy a process-unique transport identity, admission generation and slot;
no foreign connection pointer leaves C. Targeted stream open/close and stream association validate
all three fields against the current live table. Paired connection/generation arrays are allocated
atomically at startup and freed after engine teardown. See the
[peer-control contract](../../spec/jamnp-peer-control.md).
