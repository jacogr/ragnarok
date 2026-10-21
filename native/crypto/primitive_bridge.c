// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Preserve the stable primitive ABI with maintained Rust providers and current ZIP215 verification.
#include "primitive_bridge.h"
#include "rust_primitives.h"

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
/* Current Gray Paper signing schemes require ZIP215; no alternate verifier is tried. */
int rc_ed_verify(const uint8_t public_key[32], const uint8_t signature[64], const uint8_t *message, size_t length) {
    return rcr_ed_verify_zip215(public_key, signature, message, length);
}

/* Explicitly named capability sharing the current protocol verifier. */
int rc_ed_verify_zip215(const uint8_t key[32], const uint8_t sig[64], const uint8_t *data, size_t length) {
    return rcr_ed_verify_zip215(key, sig, data, length);
}
/* Explicitly erase caller-owned bytes; no caller address survives this call. */
void rc_wipe(void *data, size_t length) { rcr_wipe(data, length); }
