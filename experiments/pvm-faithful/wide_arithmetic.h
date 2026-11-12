/* Copyright (c) 2026 Ragnarök contributors */
/* SPDX-License-Identifier: MIT OR Apache-2.0 */

/* Clang equivalents of operation.rs's i128/u128 high-half products. All inputs
 * fit their signed 128-bit products except unsigned*unsigned, which intentionally
 * uses u128 for the same modulo-2^128 result as Rust wrapping_mul. */
#ifndef RAGNAROK_FAITHFUL_WIDE_ARITHMETIC_H
#define RAGNAROK_FAITHFUL_WIDE_ARITHMETIC_H
#include <stdint.h>

static inline int64_t faithful_mulh64(int64_t lhs, int64_t rhs) {
    /* Clang's signed right shift corresponds to Rust's arithmetic shift. */
    return (int64_t)(((__int128)lhs * (__int128)rhs) >> 64);
}
static inline int64_t faithful_mulhsu64(int64_t lhs, uint64_t rhs) {
    /* The signed-by-unsigned product always fits signed i128. */
    return (int64_t)(((__int128)lhs * (__int128)rhs) >> 64);
}
static inline uint64_t faithful_mulhu64(uint64_t lhs, uint64_t rhs) {
    /* Unsigned multiplication preserves the exact upper half of the full product. */
    return (uint64_t)(((unsigned __int128)lhs * (unsigned __int128)rhs) >> 64);
}
#endif
