#include "transport_bridge.h"
#include <lsquic.h>
#include <openssl/ssl.h>
#include <openssl/pool.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <netinet/in.h>
#include <sys/uio.h>
/* LSQUIC/TLS adapter only: no JAM identity, framing, codec or application protocol is implemented in C. */
struct rq_transport {
    lsquic_engine_t *engine;
    lsquic_conn_t *connection;
    SSL_CTX *tls;
    struct sockaddr_in local;
    struct lsquic_engine_settings settings;
    struct lsquic_engine_api api;
    void *user;
    rq_verify_cb verify;
    rq_send_cb send;
    rq_stream_cb stream;
    uint8_t alpn[256];
    unsigned alpn_length;
    int server, status;
};
/* Construct an IPv4 loopback socket address; the initial proof deliberately accepts no external endpoints. */
static struct sockaddr_in address(uint16_t port) {
    struct sockaddr_in a; memset(&a, 0, sizeof(a));
#ifdef __APPLE__
    a.sin_len = sizeof(a);
#endif
    a.sin_family = AF_INET; a.sin_addr.s_addr = htonl(INADDR_LOOPBACK); a.sin_port = htons(port);
    return a;
}
/* Ask the native language to validate the leaf certificate while BoringSSL retains its borrowed DER storage. */
static enum ssl_verify_result_t verify_certificate(SSL *ssl, uint8_t *alert) {
    struct rq_transport *t = SSL_CTX_get_ex_data(SSL_get_SSL_CTX(ssl), 0);
    const STACK_OF(CRYPTO_BUFFER) *chain = SSL_get0_peer_certificates(ssl);
    /* Reject absent/oversized chains before exposing a certificate to native policy. */
    if (!t || !chain || sk_CRYPTO_BUFFER_num(chain) == 0 || sk_CRYPTO_BUFFER_num(chain) > 8) {
        *alert = SSL_AD_CERTIFICATE_REQUIRED; return ssl_verify_invalid;
    }
    const CRYPTO_BUFFER *leaf = sk_CRYPTO_BUFFER_value(chain, 0);
    /* The callback decides identity; TLS separately proves possession of the certificate key. */
    if (t->verify(t->user, CRYPTO_BUFFER_data(leaf), CRYPTO_BUFFER_len(leaf))) return ssl_verify_ok;
    *alert = SSL_AD_CERTIFICATE_UNKNOWN; return ssl_verify_invalid;
}
/* Select only the configured opaque ALPN; application/version/chain meaning is supplied by the caller. */
static int choose_alpn(SSL *ssl, const uint8_t **out, uint8_t *out_length,
 const uint8_t *offered, unsigned offered_length, void *ctx) {
    (void)ssl; struct rq_transport *t = ctx;
    /* No overlap is a handshake failure rather than an implicit default protocol. */
    if (SSL_select_next_proto((uint8_t **)out, out_length, t->alpn, t->alpn_length, offered, offered_length) != OPENSSL_NPN_NEGOTIATED)
        return SSL_TLSEXT_ERR_ALERT_FATAL;
    return SSL_TLSEXT_ERR_OK;
}
/* Return the retained TLS context for this endpoint, independent of SNI hostname policy. */
static SSL_CTX *get_tls(void *ctx, const struct sockaddr *local) { (void)local; return ((struct rq_transport *)ctx)->tls; }
/* Forward bounded datagrams synchronously; a blocked sender leaves remaining packets with LSQUIC for retry. */
static int packets_out(void *ctx, const struct lsquic_out_spec *packets, unsigned count) {
    struct rq_transport *t = ctx;
    /* Flatten one QUIC datagram at a time without retaining transport-owned iovec memory. */
    for (unsigned i = 0; i < count; ++i) {
        uint8_t bytes[2048]; size_t length = 0;
        /* Enforce this proof's datagram capacity before copying any segment. */
        for (unsigned j = 0; j < packets[i].iovlen; ++j) {
            if (packets[i].iov[j].iov_len > sizeof(bytes) - length) { errno = EMSGSIZE; return i ? (int)i : -1; }
            memcpy(bytes + length, packets[i].iov[j].iov_base, packets[i].iov[j].iov_len);
            length += packets[i].iov[j].iov_len;
        }
        const struct sockaddr_in *peer = (const struct sockaddr_in *)packets[i].dest_sa;
        /* The native callback performs a nonblocking send while bytes remain valid on this stack. */
        if (!t->send(t->user, bytes, length, ntohs(peer->sin_port))) { errno = EAGAIN; return i ? (int)i : -1; }
    }
    return (int)count;
}
/* Accept only one connection in this initial proof; server callback runs after TLS handshake completion. */
static lsquic_conn_ctx_t *new_connection(void *ctx, lsquic_conn_t *connection) {
    struct rq_transport *t = ctx;
    if (t->connection && t->connection != connection) { lsquic_conn_abort(connection); return NULL; }
    t->connection = connection;
    if (t->server) t->status = 1; /* Authenticated accept; client still waits for handshake callback. */
    return (lsquic_conn_ctx_t *)t;
}
/* Capture handshake completion without confusing a newly allocated client connection with authenticated success. */
static void handshake_done(lsquic_conn_t *connection, enum lsquic_hsk_status status) {
    struct rq_transport *t = (struct rq_transport *)lsquic_conn_get_ctx(connection);
    if (t) t->status = status == LSQ_HSK_OK ? 1 : -1; /* Resumption is not enabled in this proof. */
}
/* Mark rejected/prematurely closed attempts and release the live native connection handle. */
static void connection_closed(lsquic_conn_t *connection) {
    struct rq_transport *t = (struct rq_transport *)lsquic_conn_get_ctx(connection);
    if (t) { if (t->status == 0) t->status = -1; t->connection = NULL; }
}
/* Forward new stream handles to the native protocol owner without interpreting any stream bytes. */
static lsquic_stream_ctx_t *new_stream(void *ctx, lsquic_stream_t *stream) {
    struct rq_transport *t = ctx;
    if (!stream) return NULL; /* Stream creation may be cancelled during connection shutdown. */
    lsquic_stream_wantread(stream, 1); t->stream(t->user, stream, 0);
    return (lsquic_stream_ctx_t *)t;
}
/* Native callbacks own framing state; no stream payload is processed by the bridge. */
static void stream_read(lsquic_stream_t *s, lsquic_stream_ctx_t *ctx) { struct rq_transport *t = (void *)ctx; t->stream(t->user, s, 1); }
static void stream_write(lsquic_stream_t *s, lsquic_stream_ctx_t *ctx) { struct rq_transport *t = (void *)ctx; t->stream(t->user, s, 2); }
static void stream_close(lsquic_stream_t *s, lsquic_stream_ctx_t *ctx) { struct rq_transport *t = (void *)ctx; if (t) t->stream(t->user, s, 3); }

/* Forward directional reset/STOP_SENDING so a parked native write can release its owner. */
static void stream_reset(lsquic_stream_t *s, lsquic_stream_ctx_t *ctx, int how) {
    (void)how; struct rq_transport *t = (void *)ctx;
    if (t) t->stream(t->user, s, 4); /* This proof retires the whole affected stream, preserving sibling streams. */
}

/* Callback storage has static lifetime and contains no language-owned closure. */
static const struct lsquic_stream_if callbacks = {
    .on_new_conn = new_connection, .on_conn_closed = connection_closed,
    .on_new_stream = new_stream, .on_hsk_done = handshake_done,
    .on_read = stream_read, .on_write = stream_write, .on_close = stream_close, .on_reset = stream_reset,
};
/* Own TLS/engine resources and install native policy callbacks, with complete cleanup on setup failure. */
rq_transport *rq_transport_new(int soak, int server, uint16_t local_port, const char *certificate,
 const char *key, const char *alpn, void *user, rq_verify_cb verify, rq_send_cb send, rq_stream_cb stream) {
    size_t length = strlen(alpn);
    if (!verify || !send || !stream || !length || length > 255) return NULL; /* Bounded ALPN before byte narrowing. */
    struct rq_transport *t = calloc(1, sizeof(*t));
    if (!t) return NULL; /* Typed null failure, never an application panic. */
    t->server = server; t->user = user; t->verify = verify; t->send = send; t->stream = stream; t->local = address(local_port);
    t->alpn[0] = (uint8_t)length; memcpy(t->alpn + 1, alpn, length); t->alpn_length = (unsigned)length + 1;
    if (lsquic_global_init(LSQUIC_GLOBAL_CLIENT | LSQUIC_GLOBAL_SERVER)) goto fail;
    t->tls = SSL_CTX_new(TLS_method());
    if (!t->tls || !SSL_CTX_set_ex_data(t->tls, 0, t)) goto fail;
    SSL_CTX_set_min_proto_version(t->tls, TLS1_3_VERSION); SSL_CTX_set_max_proto_version(t->tls, TLS1_3_VERSION);
    SSL_CTX_set_custom_verify(t->tls, SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT, verify_certificate);
    if (!SSL_CTX_set1_sigalgs_list(t->tls, "ed25519:ecdsa_secp256r1_sha256")) goto fail;
    /* Missing client credentials are permitted by setup only so the remote rejection can be tested. */
    if (strcmp(certificate, "-") != 0 || strcmp(key, "-") != 0) {
        if (SSL_CTX_use_certificate_chain_file(t->tls, certificate) != 1 ||
            SSL_CTX_use_PrivateKey_file(t->tls, key, SSL_FILETYPE_PEM) != 1 || !SSL_CTX_check_private_key(t->tls)) goto fail;
    }
    if (server) SSL_CTX_set_alpn_select_cb(t->tls, choose_alpn, t); /* Acceptor selects from offered protocols. */
    else if (SSL_CTX_set_alpn_protos(t->tls, t->alpn, t->alpn_length)) goto fail; /* Initiator offers exact bytes. */
    lsquic_engine_init_settings(&t->settings, server ? LSENG_SERVER : 0);
    /* Small bounded credit makes opt-in soak writers park until native readers resume. */
    if (soak) {
        t->settings.es_sfcw = 65536;
        t->settings.es_max_sfcw = 65536;
        t->settings.es_init_max_stream_data_bidi_local = 65536;
        t->settings.es_init_max_stream_data_bidi_remote = 65536;
    }
    t->settings.es_versions = 1u << LSQVER_I001; t->settings.es_support_srej = 0;
    t->api.ea_settings = &t->settings; t->api.ea_stream_if = &callbacks; t->api.ea_stream_if_ctx = t;
    t->api.ea_packets_out = packets_out; t->api.ea_packets_out_ctx = t; t->api.ea_get_ssl_ctx = get_tls;
    t->engine = lsquic_engine_new(server ? LSENG_SERVER : 0, &t->api);
    if (!t->engine) goto fail;
    return t;
fail:
    rq_transport_free(t); return NULL;
}
/* Initiate one retained loopback connection; endpoint address bytes are synchronously consumed by LSQUIC. */
int rq_connect(rq_transport *t, uint16_t port) {
    struct sockaddr_in peer = address(port);
    return lsquic_engine_connect(t->engine, LSQVER_I001, (struct sockaddr *)&t->local,
      (struct sockaddr *)&peer, t, NULL, NULL, 0, NULL, 0, NULL, 0) != NULL;
}
/* Deliver borrowed UDP bytes with caller-supplied source port and retained TLS peer context. */
int rq_packet_in(rq_transport *t, const uint8_t *bytes, size_t length, uint16_t port) {
    struct sockaddr_in peer = address(port);
    return lsquic_engine_packet_in(t->engine, bytes, length, (struct sockaddr *)&t->local, (struct sockaddr *)&peer, t, 0);
}
/* Progress packets, timers and retryable nonblocking sends on the native language's I/O thread. */
void rq_process(rq_transport *t) { lsquic_engine_send_unsent_packets(t->engine); lsquic_engine_process_conns(t->engine); }
/* Return a nonnegative relative deadline, with a conservative fallback when no native timer exists. */
int64_t rq_next_tick(rq_transport *t) { int delta; return lsquic_engine_earliest_adv_tick(t->engine, &delta) ? (delta > 0 ? delta : 0) : 10000; }
/* Expose only authentication status; application exchange is separately tracked by the native peer. */
int rq_status(rq_transport *t) { return t->status; }
/* Destruction invokes final callbacks while the native caller-owned context is still alive. */
void rq_transport_free(rq_transport *t) {
    if (!t) return;
    if (t->engine) { if (t->connection) lsquic_conn_close(t->connection); lsquic_engine_destroy(t->engine); }
    SSL_CTX_free(t->tls); free(t); lsquic_global_cleanup();
}

/* Open a raw bidirectional stream on the authenticated connection. */
void rq_open_stream(rq_transport *t) { if (t->connection && t->status == 1) lsquic_conn_make_stream(t->connection); }
/* Preserve would-block separately from EOF and fatal transport errors. */
int64_t rq_stream_read(void *s, uint8_t *bytes, size_t size) { ssize_t n = lsquic_stream_read(s, bytes, size); return n < 0 && errno == EAGAIN ? -2 : n; }
/* Native buffers stay owned by the protocol; standard stream_write copies accepted bytes into transport storage. */
int64_t rq_stream_write(void *s, const uint8_t *bytes, size_t size) { ssize_t n = lsquic_stream_write(s, bytes, size); return n < 0 && errno == EAGAIN ? -2 : n; }
/* Subscribe only while native application bytes remain pending. */
void rq_stream_want_write(void *s, int want) { lsquic_stream_wantwrite(s, want); }
/* FIN half-closes writing while reads remain active for the peer response. */
void rq_stream_fin(void *s) { lsquic_stream_shutdown(s, 1); }
/* Explicit reset/rejection closes both directions and retires callbacks before owner destruction. */
void rq_stream_abort(void *s) { lsquic_stream_close(s); }

/* Disable read readiness once the native protocol validates FIN; avoid repeated EOF callbacks. */
void rq_stream_want_read(void *s, int want) { lsquic_stream_wantread(s, want); }

/* Flush accepted application bytes even when a test deliberately withholds FIN. */
int rq_stream_flush(void *s) { return lsquic_stream_flush(s); }
