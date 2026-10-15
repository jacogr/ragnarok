#ifndef RQ_CERT_FIELDS_H
#define RQ_CERT_FIELDS_H
#include <stddef.h>
#include <stdint.h>
/* Plain owned X.509 observations. Protocol acceptance is decided in Nim. */
typedef struct rq_cert_fields {
    int ed_key, ed_signature, san_extensions, san_count, san_dns;
    size_t public_key_length, san_length;
    uint8_t public_key[32], san[256];
} rq_cert_fields;
/* Decode one complete DER certificate and copy bounded fields; return zero on malformed/oversized input. */
int rq_parse_cert(const uint8_t *der, size_t length, rq_cert_fields *out);
#endif
