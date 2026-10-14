# QUIC feasibility for JAMNP-S — 2026-10-13

Historical report: this describes the earlier dependency/wrapper approach.
The active implementation now uses [explicit adapters without Nim source
patches](quic-adapters.md). The observations below retain their original scope.

Both languages have credible routes to nonblocking QUIC. **Nim currently has
less integration work through the maintained `iftech/nim-lsquic` wrapper;
Odin has the necessary event loop but needs a transport binding.** This is a
source/API assessment, not a successful JAM handshake or the M3 gate.

Recommended first experiment: use the **same pinned LSQUIC engine and TLS
backend** in both languages. Nim uses the existing Chronos wrapper; Odin uses
small C bindings plus `core:nbio`. Sharing a mature QUIC engine is allowed by
the design; the JAM protocol, framing, peer policy and lifecycle remain native
Nim/Odin work. No libp2p dependency is needed for JAMNP-S.

## Normative networking target

Reviewed [upstream JAMNP-S simple.md](https://github.com/zdave-parity/jam-np/blob/439c45aad135dc654b3de6f56d7d694fd02b7aa8/simple.md),
commit `439c45aad135dc654b3de6f56d7d694fd02b7aa8`. This is a separate networking
revision from the unchanged Gray Paper v0.7.1 codec pin.

Required transport capabilities:

- QUIC with TLS 1.3; both peers present Ed25519 X.509 certificates.
- Validate the peer key, Ed25519 signature algorithm and single prescribed SAN.
  Enforce expected identity on dialing and certificate/key/SAN consistency on
  accepting; validator membership is application policy. Ordinary public-PKI
  trust/hostname checks cannot substitute for this identity model. Certificate
  self-signatures need not be validated, while TLS must still prove possession.
- Custom ALPN `jamnp-s/1/<genesis-prefix>` and the `/builder` variant.
- Concurrent bidirectional streams, actual QUIC stream IDs, half-close/FIN,
  reset/stop and explicit shutdown notifications.
- UP stream uniqueness/replacement and concurrent CE requests. CE success
  generally requires clean termination of both halves; reset is cancellation
  or rejection according to direction.
- A one-byte stream kind, then each message's four-byte **little-endian** byte
  length and content. This outer framing is not a JAM general-natural count.
- IPv6 peer endpoints; connection establishment in either direction.

**Version finding:** the reviewed upstream spec says ALPN version **1**. The
[JAM Docs mirror](https://jam-docs.onrender.com/knowledge/advanced/simple-networking/spec)
returned version **0** during research. Target-peer compatibility must be agreed
before an interoperability run. Pin one explicit target; do not silently copy
an old mirrored ALPN or infer networking compatibility from the codec version.

## Candidate assessment

| Route | What exists | Remaining work / concern |
| --- | --- | --- |
| Nim + maintained nim-lsquic + Chronos | Client/server/stream async API, custom certificate verifier, explicit mTLS flags and Ed25519 signature list; upstream CI configuration includes macOS arm64/Linux and Nim 2.2 refc/ORC | Prove our Nim 2.2.12 **ARC** configuration, cycles/lifetimes, cancellation, bounded memory and JAM identity checks |
| Odin + same LSQUIC engine + core:nbio | C engine with application-driven packets/timers/callbacks; installed Odin event loop supports UDP and deadlines; macOS uses kqueue | Author/review ABI bindings and TLS setup; ensure explicit callback context, buffer lifetime, per-engine client/server handling and transport scheduling |
| Both + quiche C API | Raw QUIC separate from HTTP/3; application owns I/O/timers; peer-certificate access and external SSL construction API | Good fallback, but adds Rust build tooling and BoringSSL integration. Plain verify_peer bool is insufficient for JAM custom identity checks; prove external TLS setup and ownership first |
| Both + MsQuic | C async callbacks, internal shared worker execution; client-auth and peer-certificate events | More cross-thread lifetime/handoff work, especially Nim reference ownership and Odin callback context. Reviewed platform document officially lists Windows/Linux, with other configurations experimental; macOS build instructions alone are not support proof |
| Old nim-quic + nim-ngtcp2 | Chronos/ngtcp2/BoringSSL transport and custom verifier | Both repositories are archived according to live GitHub metadata. Old nim-quic defaults to refc; unsuitable as the first maintained dependency choice |

No ready-made Odin QUIC wrapper suitable for JAM was identified in this survey;
this is a search result, not proof that none exists. Odin does **not** need
language-level async/await to multiplex streams: its event loop and C callbacks
can do that without a thread per stream. It has more application lifecycle work
than Nim's existing awaitable wrapper.

### Why the maintained Nim route matters

The current [Nim libp2p transport](https://github.com/iftech/nim-libp2p/blob/master/libp2p/transports/quictransport.nim)
imports `lsquic`; its manifest requires `lsquic >= 0.10.0`. We only use this as
integration evidence, not as JAM's protocol specification.

The reviewed [nim-lsquic](https://github.com/iftech/nim-lsquic/tree/e57027b73cbd6d9a805b93297dd7e24638db2d99)
manifest is version **0.11.2**. Its TLS setup installs a custom verifier and
`SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT`, and configures Ed25519
among accepted signature algorithms. These are useful hooks, **not existing
JAM certificate validation**. Our policy must reject ECDSA certificates even
though the transport accepts that algorithm too. Its stream close implementation
half-closes the write side, which is necessary for request-FIN/response exchange.
The reviewed CI matrix tests refc and ORC, not ARC; listed CI jobs are not a
claim that we ran them.

The wrapper vendors an **iftech LSQUIC fork**, not simply latest upstream:
`fd0d75c6584eb4c20dfa8b4b865bfe3daf5a2e52`. The proof must review that fork and
pin its BoringSSL/transitive dependency closure. Avoid pairing a wrapper's
historical generated ABI with a newer arbitrary system library.

### Ownership and scheduling requirements

Keep one owner for each connection/stream and bounded queues for pending sends,
receives and requests. An awaited write must document whether it means copied,
queued, acknowledged or completed; retain borrowed send storage until the
transport's specified completion point. A cancelled task must not free storage
while native callbacks can still reference it. FIN and reset are different
operations; shutdown must drain callbacks before releasing native contexts.

For an application-driven engine, feed received UDP datagrams, process active
connections, emit packets and schedule the next transport timer. Couple
backpressure to bounded output queues and stream flow-control credit. A single
UDP read can contain partial or multiple framed messages across QUIC stream
reads; implement incremental parsing with size checks before allocation.

Use the same engine/TLS revision and equivalent resource policies in both
languages. Compare application complexity, allocation behavior, throughput and
latency; a faster or more convenient QUIC backend is not evidence of a better
language by itself.

## Proposed proof, before more codec work

1. **Authentication gate:** two local identities using distinct Ed25519 keys,
   proper JAM SANs, required certificates and selected JAM ALPN. Test both
   initiator roles, valid peers, absent cert, wrong key type, wrong SAN, wrong
   expected server key, wrong chain ALPN and missing/mismatched ALPN. Keep early
   data/resumption disabled initially so authentication behavior is explicit.
   Repeat with Nim ARC; do not silently switch memory managers to obtain a pass.
2. **Minimal JAM exchange:** CE 143 preimage request, using an in-memory fixture
   map: stream-kind byte, framed 32-byte hash request, request FIN, framed
   preimage response and response FIN. Include unknown-key rejection, many
   concurrent requests, split/coalesced reads and over-limit lengths. A single
   message containing only preimage bytes does not need an additional natural
   blob count inside the four-byte network frame.
3. **Lifecycle/scaling gate:** delayed reader, bounded send queues, stream limits,
   timeout and cancellation during read/write, reset on each side, peer loss,
   graceful shutdown, reconnect and repeated allocation/leak checks. Exercise
   multiple connections/streams and record OS thread counts; they must not grow
   one-for-one with streams/connections. Add IPv6 loopback and Linux execution.
4. **Interoperability:** Nim-to-Odin and Odin-to-Nim, then an independent JAMNP-S
   peer pinned to the same protocol version. Same-engine cross-language success
   alone is not independent transport/protocol conformance.

UP stream replacement and persistent announcement framing should follow the
minimal exchange; complete block announcements need codecs that are still
unfinished. Performance measurements come after correctness and lifetime checks.

## Evidence and limits

Read repository instructions/design, upstream spec and native transport source
snapshots. Queried live GitHub metadata for maintenance state and commit pins;
inspected the installed Odin 2026-10 core:nbio implementation. No upstream build
script was executed and no transport dependency was installed. No QUIC handshake,
load benchmark, Linux run or ARC transport test was performed in this assessment.
Research revisions and selected engine pin are in
[networking-research.json](../spec/networking-research.json).

Additional primary sources:
[LSQUIC API/tutorial](https://lsquic.readthedocs.io/en/latest/tutorial.html),
[Odin nbio](https://pkg.odin-lang.org/core/nbio/),
[quiche C API](https://github.com/cloudflare/quiche/blob/925b225825e2188f8e58e359114150500557bf61/quiche/include/quiche.h),
[MsQuic execution](https://microsoft.github.io/msquic/msquicdocs/docs/Execution.html),
[MsQuic platforms](https://microsoft.github.io/msquic/msquicdocs/docs/Platforms.html),
[archived ngtcp2 wrapper](https://github.com/vacp2p/nim-ngtcp2).

Follow-up: the [initial macOS transport proof](quic-proof.md) now runs
authentication and concurrent CE 143 exchange in both languages. Its measured
results supersede this document's research-only status for that bounded slice.
