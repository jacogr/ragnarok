#ifndef RQ_TRANSPORT_BRIDGE_H
#define RQ_TRANSPORT_BRIDGE_H
#include <stdint.h>
#include <stddef.h>
/* Opaque transport owner; TLS policy and UDP/event-loop work stay in the native language. */
typedef struct rq_transport rq_transport;
typedef int (*rq_verify_cb)(void *, const uint8_t *, size_t);
typedef void (*rq_stream_cb)(void *, void *, int);
typedef int (*rq_send_cb)(void *, const uint8_t *, size_t, uint16_t);
/* Create a bounded single-peer TLS/QUIC proof endpoint. Strings need only live during this call. */
rq_transport *rq_transport_new(int server, uint16_t local_port, const char *certificate,
 const char *key, const char *alpn, void *user, rq_verify_cb verify, rq_send_cb send, rq_stream_cb stream);
/* Initiate one loopback connection; server receives through packet_in instead. */
int rq_connect(rq_transport *, uint16_t remote_port);
/* Feed borrowed datagrams synchronously; payload storage is not retained. */
int rq_packet_in(rq_transport *, const uint8_t *, size_t, uint16_t remote_port);
/* Drive scheduled protocol work and expose the next relative timer in microseconds. */
void rq_process(rq_transport *);
int64_t rq_next_tick(rq_transport *);
/* Zero pending, one authenticated, minus one failed; not an application-protocol success marker. */
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
#endif
