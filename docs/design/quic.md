# QUIC networking

[Design overview](../design.md). Detailed feature contracts live in `spec/`; routine increments
update their feature contract rather than appending progress here.

`src/quic/` owns JAM identities, DER/framing checks, stream policy and lifetimes. A bounded POSIX
nonblocking UDP dispatcher drives the maintained LSQUIC/TLS bridge. No stream or connection creates
an OS thread. Optional RingVRF verification uses two workers and four total owned job slots.
`peer.nim` is the bounded CLI. The standalone `session.nim` module privately owns peer/stream
state, callbacks and retained mesh coordination; only lifecycle entry points are exported.
