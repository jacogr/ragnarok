/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0 */
/* Verification-only raw reads calibrate the sanitizer on native stack and C heap storage. */
#ifndef PVM_SANITIZER_CONTROL_H
#define PVM_SANITIZER_CONTROL_H
#include <stdint.h>
#include <stdlib.h>
/* Keep the raw read visible so diagnostics identify the intended one-byte access. */
static __attribute__((noinline)) uint8_t pvm_sanitizer_read(const volatile uint8_t *bytes, uint64_t offset) {
    return bytes[offset];
}
/* The positive branch frees after reading; the negative branch deliberately frees before it. */
static __attribute__((noinline)) uint8_t pvm_sanitizer_heap(uint8_t dangling) {
    uint8_t *bytes = (uint8_t *)malloc(8);
    /* Allocation failure cannot substitute for the expected sanitizer finding. */
    if (bytes == NULL) abort();
    bytes[0] = 42;
    if (dangling != 0) {
        free(bytes);
        return pvm_sanitizer_read(bytes, 0);
    }
    uint8_t value = pvm_sanitizer_read(bytes, 0);
    free(bytes);
    return value;
}
#endif
