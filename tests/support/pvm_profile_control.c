/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Calibrate function-scoped Callgrind collection with selected and excluded work.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static volatile uint64_t observed = 0;

__attribute__((noinline)) void pvm_profile_inside(uint64_t value) {
    /* Real nested calls calibrate cost flushing beyond a leaf-only selected function. */
    observed += value;
}

__attribute__((noinline)) void pvm_profile_selected(void) {
    /* Observable bounded arithmetic retains an actual selected native function. */
    for (uint64_t i = 0; i < 128; ++i) pvm_profile_inside(i);
}

__attribute__((noinline)) void pvm_profile_outside(void) {
    /* Excluded work must never appear in the selected call graph. */
    for (uint64_t i = 0; i < 256; ++i) observed += i;
}

int main(int argc, char **argv) {
    /* Accept only the explicit repeated-call calibration; unknown modes fail. */
    int twice = argc == 2 && strcmp(argv[1], "twice") == 0;
    if (argc != 1 && !twice) return 3;
    /* The successful process contains both scopes; only selection changes its counter evidence. */
    pvm_profile_outside();
    pvm_profile_selected();
    /* Repeating identical selected work calibrates complete return dumps without changing its function body. */
    if (twice) pvm_profile_selected();
    if (observed != (twice ? 48896 : 40768)) return 2;
    puts("PVM profile calibration passed");
    return 0;
}
