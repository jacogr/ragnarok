# Nonblocking JAM networking

`src/quic/transport.nim` maintains a narrow adapter over pristine pinned LSQUIC/BoringSSL through
`native/quic/`. Nim owns identity, DER/certificate observations, ALPN/framing and CE 143 policy.
One bounded POSIX readiness dispatcher handles nonblocking UDP, bounded transport batches and application deadlines.
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

## Nimony migration slice

The experimental branch now uses `src/quic/io.nim` for nonblocking loopback UDP and a synchronous
poll dispatcher capped at two sockets and ten milliseconds. It uses public OS headers/bindings,
with no worker pool or compiler/dependency patches. Non-copyable endpoint owners unregister before
close on explicit retirement or scope exit; dispatcher ownership is acyclic. Native engines still
require explicit teardown while their callback owners remain stable.

Local checked ARC/Clang LTO tests pass 1,024 idle/ready retirement cases over IPv4/IPv6, including
scope exit and port rebind, shared readiness/data routing, flags, admission and setup failures.
A further 1,000 warmed explicit/automatic scopes check release of retained ARC dispatcher metadata.
The unchanged pinned native library also passes 16 standalone engine cycles and four shared pairs,
including failure recovery and independent sibling retirement. Nimony Linux CI includes this slice;
actual Linux confirmation remains separate.

The peer executable and broad lifecycle claims above describe the historical implemented behavior;
they are still migration gates on this branch. Next: peer identity/DER/framing and the original
malformed-input selftests, followed by authenticated exchanges, services, mesh/resilience and
proof offload. See the [cumulative Nimony evidence](nimony-trial.md).
