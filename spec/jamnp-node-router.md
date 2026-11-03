# Bounded authenticated node stream owner

Target: JAMNP-S `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, connections, UP0 and
canonical CE128/129/143 responder routing. Dependency pins are unchanged. This component does
not complete the ordinary executable's node integration, synchronization, consensus finality,
validator protocols or the remaining distribution/audit methods.

`src/jamnp-s/node.nim` owns `NodeConnections`, stable fixed peer/frame arrays and detached local
announcement bytes. Startup requires a complete canonical view with explicitly selected trusted
finality. An absent finalized block returns `NoFinality`; neither best head nor peer claims supply
that authority. Local handshake/header bytes are encoded under the caller's canonical read gate.
The native callbacks retain no canonical header, map, view or worker graph. Subsequent `advance`
refreshes this detached context and applies authenticated validator admission transitions.

A startup-only inspection callback in `NodeConnections` rejects streams before committing its
raw routing slot. Each peer has one unclassified selector reservation, up to two persistent frames
(including a closing replacement), and two canonical reads. Globally at most 64 read frames exist.
The configured raw capacity must cover `3*logicalPeerCapacity+64`, with a hard 16384-slot ceiling.
Read saturation therefore retains space for other peers' selectors and persistent streams.
Rejected streams acquire no application route. The default raw capacity remains 4096; larger
validator populations must explicitly configure enough slots for this stronger reservation policy. Buffers and reservations remain charged until
actual native retirement, including after reset or connection-close notification. A directional native reset explicitly
retires the application's remaining directions; merely disabling callbacks would strand read slots.

Only the connection initiator opens UP0. The greatest observed persistent stream ID is a
connection-lifetime watermark, recorded before parsing a replacement. Lower claims are revoked
immediately; a delayed lower stream cannot regain eligibility after a higher malformed stream.
Copied `NodeClaims` retain authenticated peer generation and stream ID, but their hashes/slots
remain untrusted advertisements. Unsupported selectors reset the individual stream.

UP0 initially admits only a bounded handshake-sized message (at most 45+36*leafLimit bytes),
then switches to the larger announcement ceiling after successful decoding. Incomplete input is
incrementally allocated. The parent accounts 16MiB of handshake bodies,32MiB of announcement
bodies,32MiB of queued output and 32MiB of canonical replies. Owned sequence capacity can exceed
logical length by the allocator's growth factor. Prefix buffers and per-frame parser state are
fixed. Announcement output reserves 1MiB for local handshakes independently of broadcast pressure.
Callbacks perform at most 4096-byte I/O chunks; host passes rotate bounded scan cursors, process
at most four messages, queue four opens and broadcast four headers per poll.

CE128/129/143 use the shared exact request/FIN parser. `takeRead` returns a fixed request plus
opaque peer-generation/slot/nonwrapping-serial ticket. Hosts capture and submit a managed network
read, continue polling only detached network data while the worker owns the canonical graph,
then collect before responding. Reset/retirement invalidates the ticket; stale replies cannot
target reused slots. Cancelling a stream never releases the worker's graph lease: collect or
joined shutdown is still required. A busy/missing read is explicitly rejected, not encoded as an
empty success. Reply buffers are charged before they enter the route.

Selectors have a 5s deadline; canonical reads have 30s inactivity and 120s absolute deadlines.
Persistent handshakes have 5s, and incomplete input/output messages 60s. Peers without a usable
required UP0 handshake are disconnected after their grace period. A backward host clock stops
the actor. Native connection idle/keepalive policy is specified separately in
[jamnp-node-liveness.md](jamnp-node-liveness.md).

`make unit SUITE=jamnp_node_service` covers default/failing factories, explicitly absent finality,
real mutually authenticated TLS, independent literal handshake/CE128 bytes, delayed lower UP0,
failed higher replacement, persistent capacity under per-peer read saturation, request FIN gates,
managed worker reply and cancellation, unsupported-method reset with a healthy connection, and
automatic UP0 and subsequent header broadcast between production owners on IPv4/IPv6,
repeated real transcript ARC balance, and 1000 complete success/failure factory lifetimes with
balanced ARC occupancy. Actual ARC lowering also rejects duplication of `NodeService`, whose
native callback addresses must remain stable. Supporting route
suites separately cover CE129 proofs and CE143 canonical full-hash checks. Ordinary Services/CLI
wiring and outbound read scheduling remain separate integration work; these tests do not claim
complete JAMNP-S compatibility.
