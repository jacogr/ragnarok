/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0 */

/* Primitive equivalent of picosimd's i8x32::most_significant_bits. Scheduling,
 * vector arithmetic and resource ownership remain in simulator.nim. Only its C
 * translation unit is built with AVX2 on x86, matching upstream target_feature. */
#ifndef RAGNAROK_FAITHFUL_SIMULATOR_SIMD_H
#define RAGNAROK_FAITHFUL_SIMULATOR_SIMD_H
#include <stdint.h>
#if defined(__x86_64__)
#include <immintrin.h>
static inline __attribute__((target("avx2"))) uint32_t
faithful_simulator_mask(const int8_t *lanes) {
    /* Unaligned loads preserve the portable array's ordinary alignment. */
    return (uint32_t)_mm256_movemask_epi8(_mm256_loadu_si256((const __m256i *)lanes));
}
#else
static inline uint32_t faithful_simulator_mask(const int8_t *lanes) {
    /* The pinned picosimd ARM implementation uses this same portable fallback. */
    uint32_t result = 0;
    for (unsigned lane = 0; lane < 32; ++lane) {
        result |= ((uint32_t)(uint8_t)lanes[lane] >> 7) << lane;
    }
    return result;
}
#endif
#endif
