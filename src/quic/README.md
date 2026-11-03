# QUIC transport

[Source guide](../README.md) · [Networking design](../../docs/design/quic.md)

This folder owns the nonblocking transport beneath JAMNP-S. [`io.nim`](io.nim) provides
POSIX UDP readiness and bounded polling. [`address.nim`](address.nim) owns copied numeric
IP/port tuples; explicit address bindings preserve full source/destination routing while legacy
port-only entry points retain their loopback scope. [`transport.nim`](transport.nim) owns the narrow
LSQUIC/TLS bridge, callback lifetimes, UDP endpoints and primitive certificate observations.
The maintained native bridge lives in [`native/quic/`](../../native/quic/README.md).

JAM peer identities, ALPN use, message framing, stream semantics, sessions and download
coordination live in [`src/jamnp-s/`](../jamnp-s/README.md). Native callbacks borrow stable
owners synchronously; endpoints retire callbacks before closing foreign resources.

Explicit dispatcher capacities support up to4096 copied registrations, with fair batches of
at most64 events through `waitBatch`. Shared owners route each current-turn event with
`ownsReady`/`processReady` and progress native timers separately with `processTimers`. Endpoint
replacement follows the complete ready batch. Default standalone/pair entry points retain their
original budgets. See the [capacity contract](../../spec/jamnp-capacity.md).
