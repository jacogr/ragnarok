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
    /* Stable bounded handles belong to the engine until on_conn_closed; no application payload lives here. */
    lsquic_conn_t *connections[16];
    unsigned active, accepted, closed, peak, authenticated;
    int multi, persistent, ipv6, global_owned;
    SSL_CTX *tls;
    struct sockaddr_in local;
    struct sockaddr_in6 local6;
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
/* All adapters currently run on one OS thread. Global TLS state outlives every engine in that process. */
static unsigned global_owners;
/* Construct an IPv6 loopback address; external endpoint routing remains outside this bounded proof. */
static struct sockaddr_in6 address6(uint16_t port) {
    struct sockaddr_in6 a; memset(&a, 0, sizeof(a));
#ifdef __APPLE__
    a.sin6_len = sizeof(a);
#endif
    a.sin6_family = AF_INET6; a.sin6_addr = in6addr_loopback; a.sin6_port = htons(port);
    return a;
}
/* Borrow the endpoint's stable address in its configured socket family. */
static const struct sockaddr *local_address(struct rq_transport *t) {
    return t->ipv6 ? (const struct sockaddr *)&t->local6 : (const struct sockaddr *)&t->local;
}
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
        const struct sockaddr *peer = packets[i].dest_sa;
        uint16_t port = peer->sa_family == AF_INET6
          ? ((const struct sockaddr_in6 *)peer)->sin6_port : ((const struct sockaddr_in *)peer)->sin_port;
        /* The native callback performs a nonblocking send while bytes remain valid on this stack. */
        if (!t->send(t->user, bytes, length, ntohs(port))) { errno = EAGAIN; return i ? (int)i : -1; }
    }
    return (int)count;
}
/* Retain bounded connection handles; service mode isolates connection lifecycle from endpoint status. */
static lsquic_conn_ctx_t *new_connection(void *ctx, lsquic_conn_t *connection) {
    struct rq_transport *t = ctx;
    /* Single-peer proofs retain their original ceiling; service admits at most sixteen authenticated peers. */
    if ((!t->multi && t->active) || t->active == 16) {
        lsquic_conn_abort(connection); return NULL;
    }
    /* A vacant slot remains valid until this connection's final close callback. */
    for (unsigned i = 0; i < 16; ++i) {
        if (!t->connections[i]) { t->connections[i] = connection; break; }
    }
    ++t->active; ++t->accepted;
    if (t->active > t->peak) t->peak = t->active; /* Observe actual overlap, not process concurrency alone. */
    if (!t->multi) t->connection = connection; /* Single-peer stream API names the retained connection in either role. */
    if (t->server) { t->status = 1; ++t->authenticated; } /* Acceptor callback follows authenticated handshake promotion. */
    return (lsquic_conn_ctx_t *)t;
}
/* Capture client authentication; a failed service connection never poisons the listener. */
static void handshake_done(lsquic_conn_t *connection, enum lsquic_hsk_status status) {
    struct rq_transport *t = (struct rq_transport *)lsquic_conn_get_ctx(connection);
    /* Keep successful authentication evidence after duplicate close races the other engine. */
    if (t && !t->server && status == LSQ_HSK_OK) ++t->authenticated;
    if (t && !t->multi) t->status = status == LSQ_HSK_OK ? 1 : -1; /* Resumption remains disabled. */
}
/* Retire exactly one retained handle; TLS rejects before promotion do not consume an authenticated slot. */
static void connection_closed(lsquic_conn_t *connection) {
    struct rq_transport *t = (struct rq_transport *)lsquic_conn_get_ctx(connection);
    if (!t) return; /* Over-capacity attempts have no retained native owner. */
    /* Release only the slot belonging to this close; other peers keep their contexts and streams. */
    for (unsigned i = 0; i < 16; ++i) {
        if (t->connections[i] == connection) {
            t->connections[i] = NULL; --t->active; ++t->closed; break;
        }
    }
    if (!t->multi) { t->status = t->persistent ? 0 : (t->status == 0 ? -1 : t->status); t->connection = NULL; } /* Retained engines become idle; one-shot proofs preserve terminal outcomes. */
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
    if (soak < 0 || soak > 3 || (soak == 2 && !server) || !verify || !send || !stream || !length || length > 255) return NULL; /* Bounded ALPN before byte narrowing. */
    struct rq_transport *t = calloc(1, sizeof(*t));
    if (!t) return NULL; /* Typed null failure, never an application panic. */
    t->persistent = soak == 3; t->multi = soak == 2; t->server = server; t->user = user; t->verify = verify; t->send = send; t->stream = stream; t->local = address(local_port);
    t->alpn[0] = (uint8_t)length; memcpy(t->alpn + 1, alpn, length); t->alpn_length = (unsigned)length + 1;
    /* Initialize once, so constructing a second engine cannot reseed state used by the first. */
    if (!global_owners && lsquic_global_init(LSQUIC_GLOBAL_CLIENT | LSQUIC_GLOBAL_SERVER)) goto fail;
    ++global_owners; t->global_owned = 1;
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
    /* Service streams have bounded transport credit as well as native application slots. */
    if (t->multi) { t->settings.es_init_max_streams_bidi = 8; t->settings.es_idle_timeout = 2; } /* Bounded crashed-peer retirement. */
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
    /* A retained single-peer engine cannot overwrite a still-live or handshaking connection. */
    if (t->server || t->active || t->connection) return 0;
    t->status = 0;
    struct sockaddr_in peer = address(port); struct sockaddr_in6 peer6 = address6(port);
    return lsquic_engine_connect(t->engine, LSQVER_I001, local_address(t),
      t->ipv6 ? (struct sockaddr *)&peer6 : (struct sockaddr *)&peer, t, NULL, NULL, 0, NULL, 0, NULL, 0) != NULL;
}
/* Deliver borrowed UDP bytes with caller-supplied source port and retained TLS peer context. */
int rq_packet_in(rq_transport *t, const uint8_t *bytes, size_t length, uint16_t port) {
    struct sockaddr_in peer = address(port); struct sockaddr_in6 peer6 = address6(port);
    return lsquic_engine_packet_in(t->engine, bytes, length, local_address(t),
      t->ipv6 ? (struct sockaddr *)&peer6 : (struct sockaddr *)&peer, t, 0);
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
    if (t->engine) lsquic_engine_destroy(t->engine); /* Final callbacks retire all retained connections before free. */
    SSL_CTX_free(t->tls);
    /* Cleanup occurs only after the final engine is destroyed; failed setup releases only its acquired lease. */
    if (t->global_owned && --global_owners == 0) lsquic_global_cleanup();
    free(t);
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

/* Queue a graceful close while UDP and callback owners still live; destruction alone cannot send packets. */
void rq_disconnect(rq_transport *t) { if (t->connection) lsquic_conn_close(t->connection); }
/* Endpoint-owned counters avoid exposing raw connection handles to application code. */
uint64_t rq_peer_metric(rq_transport *t, int metric) {
    /* Invalid trusted metric selectors have no meaningful observation. */
    switch (metric) {
    case 0: return t->active; /* Currently retained authenticated server peers (client slots may still handshake). */
    case 1: return t->accepted; /* Lifetime promoted connections, including later reconnects. */
    case 2: return t->closed; /* Retired promoted connections. */
    case 3: return t->peak; /* Maximum real connection overlap. */
    case 4: return t->authenticated; /* Lifetime successful handshakes, retained after close. */
    default: return 0;
    }
}

/* Compare the owning connections of two live stream handles; retain no connection pointer after this call. */
int rq_stream_same_peer(void *a, void *b) { return lsquic_stream_conn(a) == lsquic_stream_conn(b); }

/* Retain a single-peer IPv6 engine across reconnects; role is fixed by LSQUIC, policy stays native. */
rq_transport *rq_transport_new_ipv6(int server, uint16_t port, const char *cert, const char *key,
 const char *alpn, void *user, rq_verify_cb verify, rq_send_cb send, rq_stream_cb stream) {
    rq_transport *t = rq_transport_new(3, server, port, cert, key, alpn, user, verify, send, stream);
    if (t) { t->ipv6 = 1; t->local6 = address6(port); } /* Address selection happens before any engine processing. */
    return t;
}
/* IETF bidirectional stream IDs encode their initiator in bit zero, independently of connection direction. */
int rq_stream_local(rq_transport *t, void *stream) { return (lsquic_stream_id(stream) & 1) == (unsigned)t->server; }

/* Release the application read half after native framing has validated FIN; writing may still hold a reply. */
void rq_stream_read_done(void *stream) { lsquic_stream_shutdown(stream, 0); }
