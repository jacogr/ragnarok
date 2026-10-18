// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

#include "transport_bridge.h"
#include <lsquic.h>
#include <openssl/ssl.h>
#include <openssl/pool.h>
#include <openssl/x509.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <netinet/in.h>
#include <sys/uio.h>
/* LSQUIC/TLS adapter only: no JAM identity, framing, codec or application protocol is implemented in C. */
/* Fixed observation slots outlive their borrowed SSL key until its ex-data destructor releases them. */
struct rq_handshake {
    rq_transport *owner;
    const SSL *ssl;
    unsigned slot;
    int settled, overflow;
};
struct rq_transport {
    lsquic_engine_t *engine;
    lsquic_conn_t *connection;
    /* Stable bounded handles belong to the engine until on_conn_closed; no application payload lives here. */
    lsquic_conn_t *connections[RQ_PEER_SLOTS];
    unsigned active, accepted, closed, peak, authenticated, capacity_rejected;
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
    rq_handshake_cb handshake;
    rq_peer_cb peer;
    int destroying, packets_seen;
    struct rq_handshake handshakes[RQ_HANDSHAKE_SLOTS], overflow_handshake;
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
/* Copy public endpoint metadata while the connection lives; no sockaddr pointer escapes. */
static int peer_address(lsquic_conn_t *connection, uint8_t address[16], uint16_t *port) {
    const struct sockaddr *local = NULL, *remote = NULL;
    if (!connection || lsquic_conn_get_sockaddr(connection, &local, &remote) != 0 || !remote)
        return 0; /* Missing metadata cannot become an invented all-zero endpoint. */
    if (remote->sa_family == AF_INET6) {
        const struct sockaddr_in6 *peer = (const struct sockaddr_in6 *)remote;
        memcpy(address, &peer->sin6_addr, 16); *port = ntohs(peer->sin6_port);
    } else if (remote->sa_family == AF_INET) {
        const struct sockaddr_in *peer = (const struct sockaddr_in *)remote;
        address[10] = address[11] = 255; /* Canonical IPv4-mapped IPv6 address. */
        memcpy(address + 12, &peer->sin_addr, 4); *port = ntohs(peer->sin_port);
    } else {
        return 0; /* Unsupported families remain missing observations. */
    }
    return 1;
}
/* One process-lifetime BoringSSL index; every engine is driven by the same selector thread. */
static int handshake_index = -1;
/* SSL destruction must not dereference SSL itself: BoringSSL documents parent as unavailable here. */
static void handshake_freed(void *parent, void *ptr, CRYPTO_EX_DATA *data, int index,
                            long argl, void *argp) {
    (void)parent; (void)data; (void)index; (void)argl; (void)argp;
    struct rq_handshake *record = ptr;
    if (!record) return; /* SSL objects that never started a handshake have no observation. */
    struct rq_transport *t = record->owner;
    if (t->handshake) {
        if (record->overflow) {
            /* An untracked handshake has one terminal outcome; account for it without a false correlation. */
            t->handshake(t->user, RQ_HANDSHAKE_SLOTS, RQ_HANDSHAKE_DROPPED, NULL, 0, NULL, 0);
        } else if (!record->settled) {
            /* No successful TLS completion occurred before destruction, including endpoint cancellation. */
            t->handshake(t->user, record->slot, RQ_HANDSHAKE_FAILED, NULL, 0, NULL, 0);
        }
    }
    if (!record->overflow) record->ssl = NULL; /* The fixed slot can be reused only after SSL destruction. */
}
/* Observe documented TLS start/done signals only; no deprecated state-machine details are inspected. */
static void handshake_info(const SSL *ssl, int type, int value) {
    (void)value;
    struct rq_transport *t = SSL_CTX_get_ex_data(SSL_get_SSL_CTX(ssl), 0);
    if (!t || !t->handshake || !t->server) return; /* Disabled/client transports preserve their old callbacks. */
    if (type == SSL_CB_HANDSHAKE_START) {
        if (SSL_get_ex_data(ssl, handshake_index)) return; /* A repeated start must not allocate a second attempt. */
        struct rq_handshake *record = &t->overflow_handshake;
        for (unsigned i = 0; i < RQ_HANDSHAKE_SLOTS; ++i) {
            if (!t->handshakes[i].ssl) { record = &t->handshakes[i]; break; } /* First reusable bounded slot. */
        }
        record->settled = 0;
        if (!record->overflow) record->ssl = ssl; /* Identity only; never dereferenced after its destructor starts. */
        if (!SSL_set_ex_data((SSL *)ssl, handshake_index, record)) {
            if (!record->overflow) record->ssl = NULL; /* Allocation failure must not leak an observation slot. */
            t->handshake(t->user, RQ_HANDSHAKE_SLOTS, RQ_HANDSHAKE_DROPPED, NULL, 0, NULL, 0);
            return;
        }
        if (record->overflow) {
            /* Saturation affects observations only: TLS admission and existing connection limits are unchanged. */
            t->handshake(t->user, RQ_HANDSHAKE_SLOTS, RQ_HANDSHAKE_DROPPED, NULL, 0, NULL, 0);
            return;
        }
        lsquic_conn_t *connection = lsquic_ssl_to_conn(ssl);
        uint8_t address[16] = {0};
        uint16_t port = 0;
        if (!peer_address(connection, address, &port)) {
            t->handshake(t->user, record->slot, RQ_HANDSHAKE_DROPPED, NULL, 0, NULL, 0);
            return; /* Missing metadata cannot be replaced by an invented remote address. */
        }
        t->handshake(t->user, record->slot, RQ_HANDSHAKE_STARTED, address, port, NULL, 0);
    } else if (type == SSL_CB_HANDSHAKE_DONE) {
        struct rq_handshake *record = SSL_get_ex_data(ssl, handshake_index);
        if (!record || record->overflow || record->settled) return; /* Overflow settles as a dropped outcome on free. */
        record->settled = 1;
        const STACK_OF(CRYPTO_BUFFER) *chain = SSL_get0_peer_certificates(ssl);
        const CRYPTO_BUFFER *leaf = chain && sk_CRYPTO_BUFFER_num(chain) > 0
          ? sk_CRYPTO_BUFFER_value(chain, 0) : NULL;
        /* Native-language policy already validated this certificate; the observer copies its public identity. */
        t->handshake(t->user, record->slot, RQ_HANDSHAKE_SUCCEEDED, NULL, 0,
                     leaf ? CRYPTO_BUFFER_data(leaf) : NULL, leaf ? CRYPTO_BUFFER_len(leaf) : 0);
    }
    /* All other info notifications are deliberately ignored. */
}
/* Install before packet processing, with no dependency changes or per-connection observer allocations. */
int rq_observe_handshakes(rq_transport *t, unsigned slots, rq_handshake_cb callback) {
    if (!t || !t->server || t->accepted || t->handshake || !callback || slots != RQ_HANDSHAKE_SLOTS) return 0;
    if (handshake_index < 0) handshake_index = SSL_get_ex_new_index(0, NULL, NULL, NULL, handshake_freed);
    if (handshake_index < 0) return 0; /* Failed observer setup leaves the transport's TLS policy unchanged. */
    for (unsigned i = 0; i < RQ_HANDSHAKE_SLOTS; ++i) {
        t->handshakes[i].owner = t; t->handshakes[i].slot = i; /* Stable addresses until engine destruction. */
    }
    t->overflow_handshake.owner = t; t->overflow_handshake.overflow = 1;
    t->handshake = callback;
    SSL_CTX_set_info_callback(t->tls, handshake_info);
    return 1;
}
/* Observe admitted peers independently of the larger pending-handshake table. */
int rq_observe_peers(rq_transport *t, unsigned slots, rq_peer_cb callback) {
    if (!t || !t->server || t->packets_seen || t->peer || !callback || slots != RQ_PEER_SLOTS)
        return 0; /* Late registration could miss the identity belonging to an already-live slot. */
    t->peer = callback;
    return 1;
}
/* Public LSQUIC certificate access is valid during server admission; Nim copies the identity. */
static void peer_accepted(rq_transport *t, lsquic_conn_t *connection, unsigned slot) {
    if (!t->server || !t->peer) return; /* Disabled telemetry performs no certificate extraction. */
    STACK_OF(X509) *chain = lsquic_conn_get_full_peer_cert_chain(connection);
    uint8_t der[8192], *cursor = der;
    int length = 0;
    if (chain && sk_X509_num(chain) > 0 && sk_X509_num(chain) <= 8) {
        /* Verification already bounded the peer chain; validate the DER extent before serialization. */
        X509 *leaf = sk_X509_value(chain, 0);
        int needed = i2d_X509(leaf, NULL);
        if (needed > 0 && needed <= (int)sizeof(der) && i2d_X509(leaf, &cursor) == needed)
            length = needed; /* No X509 or DER pointer escapes the synchronous observation. */
    }
    t->peer(t->user, slot, RQ_PEER_ACCEPTED, length ? der : NULL, (size_t)length);
    sk_X509_pop_free(chain, X509_free);
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
    if ((!t->multi && t->active) || t->active == RQ_PEER_SLOTS) {
        if (t->server && t->handshake) {
            /* Admission refusal is independent of TLS success and consumes no retained peer slot. */
            uint8_t address[16] = {0};
            uint16_t port = 0;
            int known = peer_address(connection, address, &port);
            t->handshake(t->user, RQ_HANDSHAKE_SLOTS, RQ_ADMISSION_REFUSED,
                         known ? address : NULL, port, NULL, 0);
        }
        ++t->capacity_rejected; lsquic_conn_abort(connection); return NULL;
    }
    /* A vacant slot remains valid until this connection's final close callback. */
    for (unsigned i = 0; i < RQ_PEER_SLOTS; ++i) {
        if (!t->connections[i]) {
            t->connections[i] = connection;
            peer_accepted(t, connection, i); /* Authenticated identity belongs to this retained slot only. */
            break;
        }
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
    for (unsigned i = 0; i < RQ_PEER_SLOTS; ++i) {
        if (t->connections[i] == connection) {
            if (t->server && t->peer && !t->destroying)
                t->peer(t->user, i, RQ_PEER_CLOSED, NULL, 0); /* Real closure precedes slot reuse. */
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
    if (soak < 0 || soak > 5 || ((soak == 2 || soak == 5) && !server) || !verify || !send || !stream || !length || length > 255) return NULL; /* Bounded ALPN before byte narrowing. */
    struct rq_transport *t = calloc(1, sizeof(*t));
    if (!t) return NULL; /* Typed null failure, never an application panic. */
    t->persistent = soak >= 3; t->multi = soak == 2 || soak == 5; t->server = server; t->user = user; t->verify = verify; t->send = send; t->stream = stream; t->local = address(local_port);
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
    /* Recovery/load profiles use a two-second crash expiry and one-second liveness probes, solely for bounded experiments. */
    if (soak >= 4) { t->settings.es_idle_timeout = 2; t->settings.es_ping_period = 1; t->settings.es_init_max_streams_bidi = 8; }
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
    t->packets_seen = 1; /* Optional observers cannot be installed after incoming processing starts. */
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
    t->destroying = 1; /* Resource teardown does not itself prove an observed peer disconnection. */
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
    case 5: return t->capacity_rejected; /* Authenticated attempts refused at the fixed connection ceiling. */
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

/* Select only documented IPv6 proof profiles: 3 retained pair, 4 crash recovery, 5 bounded multi-peer load service. */
rq_transport *rq_transport_new_ipv6_profile(int profile, int server, uint16_t port,
 const char *cert, const char *key, const char *alpn, void *user, rq_verify_cb verify,
 rq_send_cb send, rq_stream_cb stream) {
    if (profile < 3 || profile > 5 || (profile == 5 && !server)) return NULL; /* No silent profile or role coercion. */
    rq_transport *t = rq_transport_new(profile, server, port, cert, key, alpn, user, verify, send, stream);
    if (t) { t->ipv6 = 1; t->local6 = address6(port); } /* Stable address precedes packet processing. */
    return t;
}
