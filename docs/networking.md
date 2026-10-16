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

The broad mesh/resilience/offload lifecycle claims above describe the historical implemented
behavior and remain migration gates on this branch. The actual peer executable now builds under
checked Nimony ARC/Clang LTO and passes its original parser/readiness and mesh-policy selftests.
The original sixteen one-shot authentication/framing scenarios and twelve additional valid cold
startups pass, with one OS thread per endpoint observed during the no-FIN case. The enabled
integration entry point also builds and passes its no-socket capture selftest. Startup/control
validation rejects nine malformed CLI cases. These are local macOS ARM64 results; Linux is pending.
Shared identity/DER and structural CE framing now
also pass their parser selftest, independent oracle and guarded-result checks. The peer delegates
these checks to `src/quic/protocol.nim`; fixture content and integration policy remain in the peer.
Enabled CE 143 fixture composition now also passes: private retained digest snapshots survive
receive-buffer overwrite, guarded results refuse failed access, and immutable fixture banks publish
only complete successful reloads. This is an integration workload, not a new normative relationship
between C.2 fields and CE query keys.
The original retained service workload now passes sixteen waves and 66 retired connections,
including two forced peer deaths, rejected authentication, parked large writes and healthy sibling
progress. The integrated digest listener passes twelve waves, 36 retired connections and 36
cancelled-snapshot release observations. Both retain one server engine across all their waves;
clients use fresh processes/connections. Post-warmup language allocation and descriptor ranges are
zero in the targeted local run; RSS ranges remain below the unchanged 16 MiB budget. Final engine
teardown passes the separate 64 KiB language-allocation allowance. These finite controlled runs do
not establish leak freedom, retained client-engine parity or general JAM interoperability.
Next: retained IPv6 mesh/reconnect lifecycle and standalone module structure, followed by broader
resilience and proof offload. See the [cumulative Nimony evidence](nimony-trial.md).
