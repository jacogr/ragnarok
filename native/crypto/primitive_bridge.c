// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

#include "primitive_bridge.h"
#include <openssl/blake2.h>
#include <openssl/curve25519.h>
#include <openssl/mem.h>
#include "KeccakSponge.h"
#include <string.h>

/* Empty messages use a valid address even when the language represents their input by NULL. */
static const uint8_t empty_message = 0;

/* One-shot output is copied only after valid argument checks; BoringSSL owns its ephemeral stack state. */
int rc_blake2b256(const uint8_t *data, size_t length, uint8_t out[32]) {
    /* Nonempty inputs and fixed output must have valid caller storage. */
    if ((!data && length) || !out) return 0;
    uint8_t digest[32];
    BLAKE2B256(data ? data : &empty_message, length, digest);
    memcpy(out, digest, sizeof(digest));
    return 1;
}

/* XKCP supplies the permutation and sponge; this ABI selects the pinned legacy Keccak-256 parameters only. */
int rc_keccak256(const uint8_t *data, size_t length, uint8_t out[32]) {
    /* Do not read absent input or modify absent destination storage. */
    if ((!data && length) || !out) return 0;
    uint8_t digest[32];
    /* Rate/capacity are bits, output length is bytes, and suffix 0x01 is legacy Keccak rather than SHA3. */
    if (KeccakWidth1600_Sponge(1088, 512, data ? data : &empty_message, length, 0x01,
                             digest, sizeof(digest)) != 0) return 0;
    memcpy(out, digest, sizeof(digest));
    return 1;
}

/* Retain no private key: expanded backend storage is cleared before every return after derivation. */
int rc_ed_public(const uint8_t seed[32], uint8_t out[32]) {
    /* A missing seed/output is an integration failure, never an implicit zero seed. */
    if (!seed || !out) return 0;
    uint8_t public_key[32], private_key[64];
    ED25519_keypair_from_seed(public_key, private_key, seed);
    OPENSSL_cleanse(private_key, sizeof(private_key));
    memcpy(out, public_key, sizeof(public_key));
    return 1;
}

/* Sign only the exact borrowed bytes using ordinary Ed25519; no prehash or application domain is selected. */
int rc_ed_sign(const uint8_t seed[32], const uint8_t *message, size_t length, uint8_t out[64]) {
    /* Argument failures must precede key derivation or any destination writes. */
    if (!seed || !out || (!message && length)) return 0;
    uint8_t public_key[32], private_key[64], signature[64];
    ED25519_keypair_from_seed(public_key, private_key, seed);
    const int success = ED25519_sign(signature, message ? message : &empty_message, length, private_key);
    OPENSSL_cleanse(private_key, sizeof(private_key));
    /* Native allocation failure exposes no partial signature to the language caller. */
    if (success != 1) return 0;
    memcpy(out, signature, sizeof(signature));
    return 1;
}

/* Preserve BoringSSL's documented verification verdict; provider acceptance policy is assessed by the shared tests. */
int rc_ed_verify(const uint8_t public_key[32], const uint8_t signature[64], const uint8_t *message, size_t length) {
    /* Malformed pointer/length inputs are ordinary failed verification. */
    if (!public_key || !signature || (!message && length)) return 0;
    return ED25519_verify(message ? message : &empty_message, length, signature, public_key);
}

/* Backend-provided explicit cleansing must not disappear under dead-store optimization. */
void rc_wipe(void *data, size_t length) {
    /* Default/empty owners have no byte range to erase. */
    if (data && length) OPENSSL_cleanse(data, length);
}
