/* Only OS address layouts and certificate ABI layout observations; no JAM framing, identity or scheduler. */
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/socket.h>
#include <unistd.h>
#include "../quic/cert_fields.h"
/* Bind one nonblocking IPv4 loopback socket, returning its actual port only on success. */
int rqm_udp_open(uint16_t port, uint16_t *bound) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return -1; /* No owner was created. */
    struct sockaddr_in a = {0}; a.sin_family = AF_INET; a.sin_port = htons(port); a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t n = sizeof(a);
    /* Any late setup failure closes the original descriptor before reporting failure. */
    if (fcntl(fd, F_SETFL, O_NONBLOCK) < 0 || bind(fd, (void *)&a, sizeof(a)) || getsockname(fd, (void *)&a, &n)) { close(fd); return -1; }
    *bound = ntohs(a.sin_port); return fd;
}
/* Borrow a Mojo-owned datagram only during this OS send; no protocol interpretation. */
int64_t rqm_udp_send(int fd, const uint8_t *data, size_t length, uint16_t port) {
    struct sockaddr_in a = {0}; a.sin_family = AF_INET; a.sin_port = htons(port); a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    return sendto(fd, data, length, 0, (void *)&a, sizeof(a));
}
/* Copy a datagram into the bounded caller owner; source port is valid only for nonnegative reads. */
int64_t rqm_udp_recv(int fd, uint8_t *data, size_t length, uint16_t *port) {
    struct sockaddr_in a = {0}; socklen_t n = sizeof(a);
    ssize_t got = recvfrom(fd, data, length, 0, (void *)&a, &n);
    if (got < 0) return errno == EAGAIN || errno == EWOULDBLOCK ? -2 : -1; /* Distinguish pending from an OS failure. */
    if (n != sizeof(a) || a.sin_family != AF_INET || a.sin_addr.s_addr != htonl(INADDR_LOOPBACK)) return -1; /* This proof owns loopback only. */
    *port = ntohs(a.sin_port); return got;
}
#ifdef RQM_LAYOUT
/* Generate layout facts from the compiler that builds the shared C extractor; Mojo never guesses aggregate offsets. */
int main(void) {
    printf("%zu %zu %zu %zu %zu %zu %zu %zu %zu %zu\n", sizeof(rq_cert_fields),
        offsetof(rq_cert_fields, ed_key), offsetof(rq_cert_fields, ed_signature),
        offsetof(rq_cert_fields, san_extensions), offsetof(rq_cert_fields, san_count),
        offsetof(rq_cert_fields, san_dns), offsetof(rq_cert_fields, public_key_length),
        offsetof(rq_cert_fields, san_length), offsetof(rq_cert_fields, public_key), offsetof(rq_cert_fields, san));
    return 0;
}
#endif
/* Observe the compiler's actual foreign-record layout; no language policy or byte interpretation lives here. */
size_t rqm_cert_layout(int field) {
    /* Only explicitly listed ABI observations can be queried; unknown fields return a rejecting sentinel. */
    switch (field) {
    case 0: return sizeof(rq_cert_fields); /* Required record capacity. */
    case 1: return offsetof(rq_cert_fields, ed_key); /* Primitive Ed25519 key algorithm flag. */
    case 2: return offsetof(rq_cert_fields, ed_signature); /* Primitive signature algorithm flag. */
    case 3: return offsetof(rq_cert_fields, san_extensions); /* Observed extension count. */
    case 4: return offsetof(rq_cert_fields, san_count); /* Observed name count. */
    case 5: return offsetof(rq_cert_fields, san_dns); /* Primitive DNS-name kind flag. */
    case 6: return offsetof(rq_cert_fields, public_key_length); /* Extracted key byte count. */
    case 7: return offsetof(rq_cert_fields, san_length); /* Extracted SAN byte count. */
    case 8: return offsetof(rq_cert_fields, public_key); /* Bounded original key bytes. */
    case 9: return offsetof(rq_cert_fields, san); /* Bounded original name bytes. */
    default: return SIZE_MAX; /* Unknown fields never select an arbitrary offset. */
    }
}
/* Public allocator observations include the SDK and native libraries; no private Modular symbols are queried. */
#ifdef __APPLE__
#include <malloc/malloc.h>
#else
#include <malloc.h>
#endif
/* Report actual live process malloc storage, distinct from RSS and from language-only owner accounting. */
uint64_t rqm_heap_used(void) {
#ifdef __APPLE__
    malloc_statistics_t stats = {0};
    malloc_zone_statistics(NULL, &stats);
    return stats.size_in_use;
#else
    struct mallinfo2 stats = mallinfo2();
    return (uint64_t)stats.uordblks + (uint64_t)stats.hblkhd;
#endif
}
/* Bind one nonblocking IPv6-only loopback socket; the caller retains readiness and transport ownership. */
int rqm_udp_open6(uint16_t port, uint16_t *bound) {
    int fd = socket(AF_INET6, SOCK_DGRAM, 0);
    /* No socket owner exists after an initial OS failure. */
    if (fd < 0) return -1;
    struct sockaddr_in6 a = {0};
    a.sin6_family = AF_INET6;
    a.sin6_port = htons(port);
    a.sin6_addr = in6addr_loopback;
#ifdef __APPLE__
    a.sin6_len = sizeof(a); /* BSD address length is OS metadata, not protocol policy. */
#endif
    int only = 1;
    socklen_t n = sizeof(a);
    /* Any late setup failure closes the exact original descriptor before returning failure. */
    if (setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &only, sizeof(only)) ||
        fcntl(fd, F_SETFL, O_NONBLOCK) < 0 || bind(fd, (void *)&a, sizeof(a)) ||
        getsockname(fd, (void *)&a, &n)) {
        close(fd);
        return -1;
    }
    *bound = ntohs(a.sin6_port);
    return fd;
}
/* Borrow one bounded native-language packet for a synchronous IPv6 send, retaining no pointer. */
int64_t rqm_udp_send6(int fd, const uint8_t *data, size_t length, uint16_t port) {
    struct sockaddr_in6 a = {0};
    a.sin6_family = AF_INET6;
    a.sin6_port = htons(port);
    a.sin6_addr = in6addr_loopback;
#ifdef __APPLE__
    a.sin6_len = sizeof(a); /* Match the platform's sockaddr ABI. */
#endif
    return sendto(fd, data, length, 0, (void *)&a, sizeof(a));
}
/* Copy only a complete bounded caller buffer; source metadata is meaningful solely after a nonnegative read. */
int64_t rqm_udp_recv6(int fd, uint8_t *data, size_t length, uint16_t *port) {
    struct sockaddr_in6 a = {0};
    socklen_t n = sizeof(a);
    ssize_t got = recvfrom(fd, data, length, 0, (void *)&a, &n);
    /* Would-block/interrupt races retry on the next bounded native readiness cycle. */
    if (got < 0) return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR ? -2 : -1;
    /* This proof attributes packets only to a full IPv6 loopback source address. */
    if (n != sizeof(a) || a.sin6_family != AF_INET6 || !IN6_IS_ADDR_LOOPBACK(&a.sin6_addr)) return -1;
    *port = ntohs(a.sin6_port);
    return got;
}
#include <pthread.h>
#include <stdlib.h>
/* Own only a POSIX mutex; queue/admission/cancellation policy stays entirely in native Mojo. */
void *rqm_mutex_new(void) {
    pthread_mutex_t *p = malloc(sizeof(*p));
    /* Partial allocation/setup never escapes as a usable synchronization owner. */
    if (!p) return NULL;
    if (pthread_mutex_init(p, NULL)) { free(p); return NULL; }
    return p;
}
/* Acquire one live opaque OS mutex; callers enforce owner lifetime and lock ordering. */
int rqm_mutex_lock(void *p) { return pthread_mutex_lock(p); }
/* Release the same OS mutex after the native-language critical section. */
int rqm_mutex_unlock(void *p) { return pthread_mutex_unlock(p); }
/* Destroy one original mutex only after every waiter/worker has joined. */
void rqm_mutex_free(void *p) { pthread_mutex_destroy(p); free(p); }
/* Own a POSIX condition variable without embedding any job data or scheduling decisions. */
void *rqm_cond_new(void) {
    pthread_cond_t *p = malloc(sizeof(*p));
    /* No partially initialized condition may be borrowed by a worker. */
    if (!p) return NULL;
    if (pthread_cond_init(p, NULL)) { free(p); return NULL; }
    return p;
}
/* Atomically release/wait/reacquire the caller's live OS mutex. */
int rqm_cond_wait(void *p, void *m) { return pthread_cond_wait(p, m); }
/* Wake one worker; native code rechecks its bounded queue predicate after acquiring the mutex. */
int rqm_cond_signal(void *p) { return pthread_cond_signal(p); }
/* Wake all existing workers for a changed hold/shutdown predicate. */
int rqm_cond_broadcast(void *p) { return pthread_cond_broadcast(p); }
/* Retire one original condition only after its workers have joined. */
void rqm_cond_free(void *p) { pthread_cond_destroy(p); free(p); }
/* Own one OS thread identifier; callback/context and every job remain native-language-owned. */
void *rqm_thread_new(void *(*callback)(void *), void *context) {
    pthread_t *p = malloc(sizeof(*p));
    /* A failed launch owns no joinable thread and cannot leak its temporary identifier storage. */
    if (!p) return NULL;
    if (pthread_create(p, NULL, callback, context)) { free(p); return NULL; }
    return p;
}
/* Join one successfully created OS worker before releasing its original identifier owner. */
int rqm_thread_join(void *p) {
    int result = pthread_join(*(pthread_t *)p, NULL);
    /* Only a completed join permits the identifier's storage to retire. */
    if (!result) free(p);
    return result;
}

/* Adapt the platform's nfds_t width at the OS boundary; no readiness policy lives in this helper. */
#include <poll.h>
int rqm_poll(void *records, size_t count, int milliseconds) {
    /* Candidate dispatchers use at most two records; reject unexpected narrowing before calling POSIX. */
    if (count > 256) { errno = EINVAL; return -1; }
    return poll((struct pollfd *)records, (nfds_t)count, milliseconds);
}
/* Express C's nullable FILE pointer in C rather than passing an integer through a foreign pointer slot. */
int rqm_flush(void) { return fflush(NULL); }
