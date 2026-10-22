// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Internal synchronous Rust ABI: fixed outputs and caller-owned, non-retained byte ranges.
#ifndef RAGNAROK_RUST_PRIMITIVES_H
#define RAGNAROK_RUST_PRIMITIVES_H
#include <stddef.h>
#include <stdint.h>
/* Boolean operations return 1 only after complete output, 0 on validation failure or unwind. */
int rcr_blake2b256(const uint8_t *, size_t, uint8_t *);
int rcr_keccak256(const uint8_t *, size_t, uint8_t *);
int rcr_ed_public(const uint8_t *, uint8_t *);
int rcr_ed_sign(const uint8_t *, const uint8_t *, size_t, uint8_t *);
int rcr_ed_verify_zip215(const uint8_t *, const uint8_t *, const uint8_t *, size_t);
/* Caller supplies live writable storage, or NULL for an empty/default owner. */
void rcr_wipe(void *, size_t);
#endif
