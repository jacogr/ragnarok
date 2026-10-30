# JAMNP-S stream lifecycle

## Persistent stream ownership

The pinned JAMNP-S “Protocols and streams” section requires UP streams to be opened only
by the connection initiator. When multiple streams of one UP kind are observed on a
connection, the greatest stream ID is retained and the others are reset/stopped.

`src/quic/transport.nim` exposes a nominal copied `NativeStreamId` from the maintained
`rq_stream_id` bridge. The bridge only calls pristine LSQUIC's public `lsquic_stream_id`;
it does not decide JAM protocol policy or retain a connection pointer. IETF QUIC stream
numbers are below 2^62. Their low bits distinguish initiator and direction: client-initiated
bidirectional streams have both bits zero. `src/jamnp-s/streams.nim` applies these facts to
JAMNP-S UP admission and greatest-ID selection. `AnnouncementRoute.bindStream` checks the
actual live native ID before installing a route or enabling callbacks.

The development/current-sync responder admits a candidate UP0 in two passes over its fixed
routing slots. First it checks every nonfailed, still-bound UP0 on the same authenticated
connection, rejecting a lower/equal candidate without changing prior routes. Then it revokes
claims on all older matching routes and resets their native streams. Only final native close
releases those slots and their byte owners. A pending route participates in replacement before
its handshake becomes known, so delayed message processing cannot create two UP0 owners.
Streams on different native connections retain independent ID spaces and cannot replace or
reject each other through this comparison.

Malformed replacement handshakes cannot revive older claims. Claims are revoked before native
reset, and failed routes do not process buffered messages. This is stream/lifetime authority
only; peer leaves remain untrusted claims and grant neither execution nor finality authority.

## Verification

The native `jamnp_persistent` regression uses ordinary JAM certificate/SAN verification and
explicit outgoing key pins. Independent senders open real QUIC streams 0/4/8 on one connection,
then send their kind/handshakes in order 0,8,4. The production responder must retain 8, revoke and
reset 0, and reject the delayed 4. On another connection, a pending ID 0 is replaced by 4 without
disturbing the first connection's ID 8. Live claim cardinality/IDs and real native reset/close
observations are required under fixed two-second deadlines. Neither sender emits FIN.

The test also checks all low-byte stream-ID role/direction combinations and the 2^62 boundary.
Removing the responder's selection call supplies the old-admission negative control; this
must fail the same live routing assertion. The complete corrected source is restored after
that control. Existing discovery and current-sync consumers must continue to pass.

General CE request/response transcripts, all-stream dispatcher integration, validator-set
connectivity and audit/state-backed services remain tracked separately in the
[full compliance inventory](jamnp-compliance.md). This UP0 correction does not close those gaps.
