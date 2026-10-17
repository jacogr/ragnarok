#ifndef RQ_TRANSPORT_BRIDGE_H
#define RQ_TRANSPORT_BRIDGE_H
#include <stdint.h>
#include <stddef.h>
/* Opaque transport owner; TLS policy and UDP/event-loop work stay in the native language. */
typedef struct rq_transport rq_transport;
typedef int (*rq_verify_cb)(void *, const uint8_t *, size_t);
typedef void (*rq_stream_cb)(void *, void *, int);
typedef int (*rq_send_cb)(void *, const uint8_t *, size_t, uint16_t);
/* Optional TLS observations borrow address/DER only during the callback, before engine teardown ends. */
enum { RQ_HANDSHAKE_SLOTS = 64, RQ_HANDSHAKE_STARTED = 0, RQ_HANDSHAKE_SUCCEEDED = 1,
       RQ_HANDSHAKE_FAILED = 2, RQ_HANDSHAKE_DROPPED = 3 };
typedef void (*rq_handshake_cb)(void *, unsigned, int, const uint8_t *, uint16_t,
                               const uint8_t *, size_t);
/* Enable once on an idle server; slot-count agreement protects the native-language fixed table. */
int rq_observe_handshakes(rq_transport *, unsigned slots, rq_handshake_cb);
/* Create a bounded TLS/QUIC proof endpoint. Mode 0 normal, 1 flow-control soak, 2 multi-peer server, 3..5 reserved for IPv6 proof profiles. Strings need only live during this call. */
rq_transport *rq_transport_new(int soak, int server, uint16_t local_port, const char *certificate,
 const char *key, const char *alpn, void *user, rq_verify_cb verify, rq_send_cb send, rq_stream_cb stream);
/* Initiate one loopback connection; server receives through packet_in instead. */
int rq_connect(rq_transport *, uint16_t remote_port);
/* Queue graceful single-connection close before stopping UDP readiness. */
void rq_disconnect(rq_transport *);
/* Read endpoint counters: 0 active, 1 accepted, 2 closed, 3 peak, 4 successful handshakes, 5 connection-capacity rejects (all bounded handles, no borrowed pointers). */
uint64_t rq_peer_metric(rq_transport *, int);
/* Feed borrowed datagrams synchronously; payload storage is not retained. */
int rq_packet_in(rq_transport *, const uint8_t *, size_t, uint16_t remote_port);
/* Drive scheduled protocol work and expose the next relative timer in microseconds. */
void rq_process(rq_transport *);
int64_t rq_next_tick(rq_transport *);
/* Zero idle/pending, one authenticated, minus one failed; not an application-protocol success marker. */
int rq_status(rq_transport *);
/* Close and destroy only after native UDP callbacks stop accessing the transport owner. */
void rq_transport_free(rq_transport *);
/* Raw stream operations preserve native framing and caller-owned application buffers. */
void rq_open_stream(rq_transport *);
int64_t rq_stream_read(void *, uint8_t *, size_t);
int64_t rq_stream_write(void *, const uint8_t *, size_t);
void rq_stream_want_read(void *, int);
void rq_stream_want_write(void *, int);
void rq_stream_fin(void *);
void rq_stream_abort(void *);
/* Explicitly transmit buffered bytes without implying application FIN. */
int rq_stream_flush(void *s);
/* Compare peer ownership only while both native streams live; no connection handle escapes. */
int rq_stream_same_peer(void *, void *);
/* IPv6 loopback proof engine retains socket/TLS/engine ownership across sequential reconnects. */
rq_transport *rq_transport_new_ipv6(int server, uint16_t port, const char *cert, const char *key,
 const char *alpn, void *user, rq_verify_cb verify, rq_send_cb send, rq_stream_cb stream);
/* Query whether a live bidirectional stream was opened locally; no connection pointer escapes. */
int rq_stream_local(rq_transport *, void *);
/* Mark the read half finished only after the native caller validates its exact message and FIN. */
void rq_stream_read_done(void *);
/* Profile 3 retains a pair, 4 uses bounded crash expiry, 5 admits sixteen peers with eight remote streams each. */
rq_transport *rq_transport_new_ipv6_profile(int profile, int server, uint16_t port, const char *cert,
 const char *key, const char *alpn, void *user, rq_verify_cb verify, rq_send_cb send, rq_stream_cb stream);
#endif
