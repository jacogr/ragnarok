# Bounded transport capacity for JAMNP-S connectivity

Authority: JAMNP-S at `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, Required connectivity.
Previous/current/next validator connectivity cannot fit a two-socket dispatcher or a fixed
sixteen-peer acceptor. This layer supplies explicit generic capacities up to4096 endpoints/peers,
retaining the old two-socket and sixteen-peer defaults. It does not implement validator
membership, builder reservations, epoch transitions or gossip policy.

Dispatcher registrations own copied descriptors only. Storage is allocated at construction,
never resized while polling, and cleared on close. A fair bounded batch operation returns at
most64 readiness events; legacy all-registration waits retain their output-size contract.
Transport owners expose synchronous readiness/timer progression for one shared dispatcher.
Ready values cannot outlive their dispatch turn or be used after replacing a descriptor.

The C bridge owns a bounded connection-handle allocation until all engine/TLS callbacks retire.
Its capacity can change only during server startup, before network processing or peer-observer
registration. Invalid sizes/allocation failures preserve the original table. Application role and
identity policy remain in Nim. Single-peer engines retain their one-connection ceiling.

Completion checks: real UDP fairness with more than two sockets and small output batches;
closed/retired descriptors; actual mutual TLS admitting twenty peers, rejecting overflow and
reusing a retired slot; unchanged default consumer and ownership/lifetime checks; production build.

The capacity witness primes actual kernel readiness before asserting batch order; no send-to-read
timing assumption releases the fairness barrier. Invalid limits are checked using otherwise valid
credentials, including a64-bit value that would narrow to the valid uint32 default16. The real TLS
case distinguishes authentication from retained server admission before selecting a peer to close.

Local macOS ARM64 checks pass: `quic_capacity` (including a fresh repeated run), `quic_io`
(1000 cycles608=>608), `jamnp_persistent`, `jamnp_alpn` and production ARC/LTO build. No pins changed.
