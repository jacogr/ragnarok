// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Extracts bounded X.509 observations and generates TLS keys/certificates using BoringSSL.
// Nim supplies protocol names, chooses paths and decides certificate acceptance.

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


#include <openssl/pem.h>
#include <openssl/mem.h>

/* Copy one bounded memory BIO without retaining foreign or caller pointers. */
static int identity_copy(BIO *bio, uint8_t *output, size_t capacity, size_t *written) {
    char *bytes = NULL;
    long length = BIO_get_mem_data(bio, &bytes);
    if (length <= 0 || (size_t)length > capacity) return 0;
    memcpy(output, bytes, (size_t)length);
    *written = (size_t)length;
    return 1;
}

int rq_identity_key(uint8_t *pem, size_t capacity, size_t *length, uint8_t public_key[32]) {
    /* Entropy and Ed25519 key generation belong to the maintained TLS implementation. */
    if (!pem || !length || !public_key) return 0;
    *length = 0;
    EVP_PKEY_CTX *context = EVP_PKEY_CTX_new_id(EVP_PKEY_ED25519, NULL);
    EVP_PKEY *key = NULL;
    BIO *bio = BIO_new(BIO_s_mem());
    size_t public_length = 32;
    int ok = context && bio && EVP_PKEY_keygen_init(context) == 1 &&
             EVP_PKEY_keygen(context, &key) == 1 &&
             EVP_PKEY_get_raw_public_key(key, public_key, &public_length) == 1 &&
             public_length == 32 && PEM_write_bio_PrivateKey(bio, key, NULL, NULL, 0, NULL, NULL) == 1 &&
             identity_copy(bio, pem, capacity, length);
    /* Every owned crypto/BIO object retires on both successful and failed generation. */
    if (bio) {
        char *private_bytes = NULL;
        long private_length = BIO_get_mem_data(bio, &private_bytes);
        if (private_length > 0) OPENSSL_cleanse(private_bytes, (size_t)private_length);
    }
    BIO_free(bio);
    EVP_PKEY_free(key);
    EVP_PKEY_CTX_free(context);
    return ok;
}

int rq_identity_cert(const uint8_t *key, size_t length, const char *dns, int days,
                     uint8_t *pem, size_t capacity, size_t *written) {
    /* The caller supplies the protocol name; enforce only bounded TLS primitive inputs here. */
    if (!key || !length || length > 4096 || !dns || !pem || !written || days < 1 || days > 3650)
        return 0;
    *written = 0;
    size_t dns_length = strlen(dns);
    if (!dns_length || dns_length > 54) return 0;
    BIO *input = BIO_new_mem_buf(key, (int)length);
    EVP_PKEY *private_key = input ? PEM_read_bio_PrivateKey(input, NULL, NULL, NULL) : NULL;
    X509 *cert = X509_new();
    BIO *output = BIO_new(BIO_s_mem());
    GENERAL_NAMES *names = GENERAL_NAMES_new();
    GENERAL_NAME *name = GENERAL_NAME_new();
    ASN1_IA5STRING *value = ASN1_IA5STRING_new();
    int named = names && name && value && ASN1_STRING_set(value, dns, (int)dns_length) == 1;
    /* Ownership moves only after each successful primitive operation. */
    if (named) {
        GENERAL_NAME_set0_value(name, GEN_DNS, value);
        value = NULL;
        named = sk_GENERAL_NAME_push(names, name) != 0;
        if (named) name = NULL;
    }
    int ok = private_key && cert && output && named &&
             X509_set_version(cert, 2) == 1 && ASN1_INTEGER_set(X509_get_serialNumber(cert), 1) == 1 &&
             X509_gmtime_adj(X509_get_notBefore(cert), -300) &&
             X509_gmtime_adj(X509_get_notAfter(cert), (long)days * 86400) &&
             X509_set_pubkey(cert, private_key) == 1;
    /* A self-signed TLS certificate has one DNS SAN and no independent chain authority. */
    if (ok) {
        X509_NAME *subject = X509_get_subject_name(cert);
        ok = X509_NAME_add_entry_by_txt(subject, "CN", MBSTRING_ASC,
                                       (const uint8_t *)"Ragnarok", -1, -1, 0) == 1 &&
             X509_set_issuer_name(cert, subject) == 1 &&
             X509_add1_ext_i2d(cert, NID_subject_alt_name, names, 0, X509V3_ADD_DEFAULT) == 1 &&
             X509_sign(cert, private_key, NULL) > 0 && PEM_write_bio_X509(output, cert) == 1 &&
             identity_copy(output, pem, capacity, written);
    }
    ASN1_IA5STRING_free(value);
    GENERAL_NAME_free(name);
    GENERAL_NAMES_free(names);
    BIO_free(output);
    X509_free(cert);
    EVP_PKEY_free(private_key);
    BIO_free(input);
    return ok;
}

void rq_identity_clear(uint8_t *bytes, size_t length) {
    /* This maintained non-elidable wipe is safe for empty scratch too. */
    if (bytes && length) OPENSSL_cleanse(bytes, length);
}
