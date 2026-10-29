// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Declares owned X.509 observations and bounded TLS identity generation primitives.
// JAM naming and acceptance policy remain in Nim.

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
/* Generate an Ed25519 PEM key and copy its raw public identity into caller-owned storage. */
int rq_identity_key(uint8_t *pem, size_t capacity, size_t *length, uint8_t public_key[32]);
/* Self-sign a certificate with the caller-selected DNS SAN; no JAM naming policy lives in C. */
int rq_identity_cert(const uint8_t *key, size_t length, const char *dns, int days,
                     uint8_t *pem, size_t capacity, size_t *written);
/* Erase private caller scratch even when serialization or publication fails. */
void rq_identity_clear(uint8_t *bytes, size_t length);
#endif
