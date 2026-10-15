# Nonblocking JAM networking

`src/quic/transport.nim` maintains a narrow adapter over pristine pinned LSQUIC/BoringSSL through
`native/quic/`. Nim owns identity, DER/certificate observations, ALPN/framing and CE 143 policy.
One selector dispatcher handles nonblocking UDP, bounded transport batches and application deadlines.
Callbacks borrow stable owners synchronously; no thread is created per connection or stream.

The retained peer executable in `src/quic/peer.nim` supports controlled authenticated exchanges,
retained listeners, IPv6 bidirectional role engines, preferred/fallback arbitration and reconnect.
Cancellation/backpressure keeps owners alive until their foreign borrows retire. Shutdown closes
engines/sockets/selectors; the optional proof queue cancels outstanding slots and joins both workers.
RingVRF offload has two fixed workers and four total owned jobs, including completed results.

Current tests cover malformed identities/framing, missing FIN, healthy siblings, peer death,
connection/stream admission recovery, descriptor/RSS/allocation bounds and cleanup. Integration
composes owned work-digest capture, requested-content Blake2b checks and CE 143 responses. The
preimage-as-digest schema is a test workload, not a new normative JAM hash relationship.

The startup harness reserves UDP and serializes reservation-to-readiness handoff; readiness requires
an exact line from a live process. It retains startup diagnostics and existing finite deadlines.
Port release/native bind is not descriptor inheritance, so unrelated processes remain an external race.

See [development commands](development.md). General validator-set management, multi-target dialing,
independent JAM-stack interoperability, production sizing and full protocol/state coverage remain open.
Pinned networking source is recorded in `spec/quic-proof-pins.json` and `vendor/jam-np`.
