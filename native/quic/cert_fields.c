// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

#include "cert_fields.h"
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <openssl/evp.h>
#include <string.h>
#include <limits.h>
/* Extract primitive certificate fields using the pinned TLS library, without JAM policy or hostname validation. */
int rq_parse_cert(const uint8_t *der, size_t length, rq_cert_fields *out) {
    /* Reject absent/oversized buffers before DER parsing or signed-size conversion. */
    if (!der || !out || !length || length > 8192 || length > LONG_MAX) return 0;
    memset(out, 0, sizeof(*out));
    const uint8_t *cursor = der;
    X509 *cert = d2i_X509(NULL, &cursor, (long)length);
    /* Require exactly one certificate, without accepting trailing unparsed bytes. */
    if (!cert || cursor != der + length) { X509_free(cert); return 0; }
    EVP_PKEY *key = X509_get_pubkey(cert);
    /* Missing public keys are malformed, irrespective of protocol policy. */
    if (!key) { X509_free(cert); return 0; }
    out->ed_key = EVP_PKEY_id(key) == EVP_PKEY_ED25519;
    out->ed_signature = X509_get_signature_nid(cert) == NID_ED25519;
    size_t raw_length = sizeof(out->public_key);
    /* Copy raw Ed25519 bytes only when the primitive exposes that key format. */
    if (out->ed_key && EVP_PKEY_get_raw_public_key(key, out->public_key, &raw_length)) out->public_key_length = raw_length;
    int index = -1;
    /* Count duplicate SAN extensions, which the protocol layer may reject. */
    while ((index = X509_get_ext_by_NID(cert, NID_subject_alt_name, index)) >= 0) ++out->san_extensions;
    GENERAL_NAMES *names = X509_get_ext_d2i(cert, NID_subject_alt_name, NULL, NULL);
    /* Absent/malformed SANs yield zero copied names rather than a fabricated hostname. */
    if (names) {
        out->san_count = (int)sk_GENERAL_NAME_num(names);
        /* A single DNS name can be copied into fixed storage; other forms remain observable as unsupported. */
        if (out->san_count == 1) {
            const GENERAL_NAME *name = sk_GENERAL_NAME_value(names, 0);
            out->san_dns = name->type == GEN_DNS;
            /* Preserve exact IA5 bytes and length, including embedded NULs for native policy rejection. */
            if (out->san_dns) {
                size_t n = (size_t)ASN1_STRING_length(name->d.dNSName);
                if (n <= sizeof(out->san)) { out->san_length = n; memcpy(out->san, ASN1_STRING_get0_data(name->d.dNSName), n); }
            }
        }
        GENERAL_NAMES_free(names);
    }
    EVP_PKEY_free(key); X509_free(cert);
    return 1;
}
