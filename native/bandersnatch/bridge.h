// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Declares the synchronous Bandersnatch C ABI used by Nim. Exposes opaque key/setup owners,
// fixed signature/proof operations and explicit release functions.

#ifndef RAGNAROK_BANDERSNATCH_H
#define RAGNAROK_BANDERSNATCH_H
#include <stddef.h>
#include <stdint.h>
/* Every operation is synchronous: borrows end on return. 0 succeeds; 1 length, 2 encoding,
   3 missing owner, 4 failed verification, 5 backend failure, 6 caught panic. Outputs change only on success. */
/* Import exactly one canonical 32-byte nonzero scalar into opaque Rust-owned storage. */
uint32_t bs_key_new(const uint8_t *, size_t, void **);
/* Destroy one key owner, zeroizing the retained scalar. All borrowed aliases become invalid. */
void bs_key_free(void *);
/* Derive a full 32-byte public encoding from a live owner. */
uint32_t bs_public(const void *, uint8_t *);
/* Sign raw input and separate additional data; output is exactly 96 bytes. */
uint32_t bs_sign(const void *, const uint8_t *, size_t, const uint8_t *, size_t, uint8_t *);
/* Verify exact proof width; return 32 output-hash bytes only after verification. */
uint32_t bs_verify(const uint8_t *, const uint8_t *, size_t, const uint8_t *, size_t, const uint8_t *, size_t, uint8_t *);
/* Own immutable parameters from the embedded pinned public SRS, capacity 1..1023. */
uint32_t bs_setup_new(size_t, void **);
/* Release exactly one Rust parameter allocation; copied aliases are borrowed. */
void bs_setup_free(void *);
/* Commit bounded ordered valid ring encodings into a 144-byte root; retain no member buffer. */
uint32_t bs_commit(const void *, const uint8_t *, size_t, uint8_t *);
/* Prove membership for a matching key/index, producing a 784-byte output/proof. */
uint32_t bs_ring_sign(const void *, const void *, size_t, const uint8_t *, size_t, const uint8_t *, size_t, const uint8_t *, size_t, uint8_t *);
/* Verify against a root and the owner's domain/SRS, yielding the verified 32-byte output. */
uint32_t bs_ring_verify(const void *, const uint8_t *, const uint8_t *, size_t, const uint8_t *, size_t, const uint8_t *, size_t, uint8_t *);
/* Canonical prime-subgroup point validation; missing/wrong-width inputs fail before decode. */
uint32_t bs_validate_public(const uint8_t *, size_t);
/* Copy the selected historical suite's 32-byte padding encoding. */
uint32_t bs_padding(uint8_t *);
#endif
