/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Calibrate function-scoped Callgrind collection with selected and excluded work.
 */
#include <stdint.h>
#include <stdio.h>

static volatile uint64_t observed = 0;

__attribute__((noinline)) void pvm_profile_selected(void) {
    /* Observable bounded arithmetic retains an actual selected native function. */
    for (uint64_t i = 0; i < 128; ++i) observed += i;
}

__attribute__((noinline)) void pvm_profile_outside(void) {
    /* Excluded work must never appear in the selected call graph. */
    for (uint64_t i = 0; i < 256; ++i) observed += i;
}

int main(void) {
    /* The successful process contains both scopes; only selection changes its counter evidence. */
    pvm_profile_outside();
    pvm_profile_selected();
    if (observed != 40768) return 2;
    puts("PVM profile calibration passed");
    return 0;
}
