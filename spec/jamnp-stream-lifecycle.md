# JAMNP-S stream lifecycle

## Persistent stream ownership

The pinned JAMNP-S “Protocols and streams” section requires UP streams to be opened only
by the connection initiator. When multiple streams of one UP kind are observed on a
connection, the greatest stream ID is retained and the others are reset/stopped.

The [stream policy](../src/jamnp-s/streams.nim) interprets copied QUIC IDs, and the
[development responder](../src/jamnp-s/devnet.nim) owns UP0 replacement and retirement.
Peer leaves remain untrusted claims. Stream authority grants neither execution nor finality.

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
