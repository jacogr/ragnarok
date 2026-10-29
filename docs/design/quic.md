# QUIC networking

[Design overview](../design.md). Detailed feature contracts live in `spec/`; routine increments
update their feature contract rather than appending progress here.

`src/quic/` owns JAM identities, DER/framing checks, stream policy and lifetimes. A bounded POSIX
nonblocking UDP dispatcher drives the maintained LSQUIC/TLS bridge. No stream or connection creates
an OS thread. Raw-block preparation uses one reusable Services worker and one outstanding input
lease after native callbacks retire; endpoint polling continues while canonical/RPC access is gated.
A finite download run retains authenticated peer connections across children. Host rearming
requires a consumed canonical adoption, native close and retired input/job leases; final shutdown
joins before borrowed owners retire. See the
[progress contract](../../spec/application-download-progress.md) and the
[download worker contract](../../spec/application-download-worker.md). Optional RingVRF verification uses two workers and four total owned job slots.
The application entry point is `src/ragnarok.nim`. `session.nim` receives validated application
configuration and privately owns peer/stream state, callbacks and retained mesh coordination.
Both peer shapes use `app/services.nim` for optional service ownership/startup; transport
callbacks retire before those shared services. Only lifecycle entry points are exported.

## Peer announcements

Optional UP0 discovery shares the authenticated outgoing catalog with CE128 through a distinct
persistent stream route. Callbacks retain bounded detached bytes; host polling decodes complete
messages and hashes announced headers. Available snapshots contain copied peer claims and source
incarnation/sequence, never validated full/light state or trusted finality. Stream or TLS retirement
revokes availability. See [continuous sync](../../spec/node-sync.md) for the trust and readiness contract.

## Canonical development block serving

`quic/devnet.nim` owns a stable noncopyable incoming endpoint, one serial outgoing endpoint and
six pinned identities. Sixteen fixed incoming stream slots copy bounded CE128 requests and serve
one canonical child from the host-published finite catalog. An absent child returns an empty
response sequence. The outgoing path requires exact framing and response FIN before returning
copied bytes to its host; it grants no execution/adoption authority. A catalog entry is published
only after ordinary candidate validation, durable journal publication and canonical installation.
Explicit teardown emits connection close while UDP is still live, retires both engines and only
then releases callback storage. No consensus execution occurs inside native callbacks.
