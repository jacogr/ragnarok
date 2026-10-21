// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Preserve the stable primitive ABI and release verification policy while sharing Rust providers.
#include "primitive_bridge.h"
#include "rust_primitives.h"
#include <openssl/curve25519.h>
static const uint8_t empty_message = 0;

/* Forward synchronous operations; Rust commits outputs only after completion and contains unwinds. */
int rc_blake2b256(const uint8_t *data, size_t length, uint8_t out[32]) {
    return rcr_blake2b256(data, length, out);
}
/* Select legacy Keccak, never SHA3 padding. */
int rc_keccak256(const uint8_t *data, size_t length, uint8_t out[32]) {
    return rcr_keccak256(data, length, out);
}
/* Expanded signing storage is owned by a Rust zeroizing guard. */
int rc_ed_public(const uint8_t seed[32], uint8_t out[32]) {
    return rcr_ed_public(seed, out);
}
/* Ordinary Ed25519 signatures retain their exact RFC 8032 bytes. */
int rc_ed_sign(const uint8_t seed[32], const uint8_t *data, size_t length, uint8_t out[64]) {
    return rcr_ed_sign(seed, data, length, out);
}
/* Preserve BoringSSL's documented verification verdict; provider acceptance policy is assessed by the shared tests. */
int rc_ed_verify(const uint8_t public_key[32], const uint8_t signature[64], const uint8_t *message, size_t length) {
    /* Malformed pointer/length inputs are ordinary failed verification. */
    if (!public_key || !signature || (!message && length)) return 0;
    return ED25519_verify(message ? message : &empty_message, length, signature, public_key);
}

/* Explicit capability for the subsequent coordinated Gray Paper upgrade. */
int rc_ed_verify_zip215(const uint8_t key[32], const uint8_t sig[64], const uint8_t *data, size_t length) {
    return rcr_ed_verify_zip215(key, sig, data, length);
}
/* Explicitly erase caller-owned bytes; no caller address survives this call. */
void rc_wipe(void *data, size_t length) { rcr_wipe(data, length); }
