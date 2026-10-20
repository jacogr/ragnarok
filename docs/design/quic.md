# QUIC networking

[Design overview](../design.md). Detailed feature contracts live in `spec/`; routine increments
update their feature contract rather than appending progress here.

`src/quic/` owns JAM identities, DER/framing checks, stream policy and lifetimes. A bounded POSIX
nonblocking UDP dispatcher drives the maintained LSQUIC/TLS bridge. No stream or connection creates
an OS thread. Raw-block preparation uses one reusable Services worker and one outstanding input
lease after native callbacks retire; endpoint polling continues while canonical/RPC access is gated.
See the [download worker contract](../../spec/application-download-worker.md). Optional RingVRF verification uses two workers and four total owned job slots.
The application entry point is `src/ragnarok.nim`. `session.nim` receives validated application
configuration and privately owns peer/stream state, callbacks and retained mesh coordination.
Both peer shapes use `app/services.nim` for optional service ownership/startup; transport
callbacks retire before those shared services. Only lifecycle entry points are exported.
