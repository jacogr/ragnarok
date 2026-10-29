/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Diagnostic-only explicit collection boundaries; no guest data or pointers enter this bridge.
 */
#ifndef RAGNAROK_PVM_PROFILE_SCOPE_H
#define RAGNAROK_PVM_PROFILE_SCOPE_H
#include <valgrind/callgrind.h>

static __attribute__((always_inline)) inline void pvm_profile_begin(void) {
    /* Collection begins at the request, independently of ARM call/return inference. */
    CALLGRIND_TOGGLE_COLLECT;
}
static __attribute__((always_inline)) inline void pvm_profile_pause(void) {
    /* Stop before caller validation, host receipts or the next invocation's setup. */
    CALLGRIND_TOGGLE_COLLECT;
}
static __attribute__((always_inline)) inline void pvm_profile_flush(void) {
    /* A complete numbered dump preserves this invocation; reset after dumping while collection is off. */
    CALLGRIND_DUMP_STATS;
    CALLGRIND_ZERO_STATS;
}
static __attribute__((always_inline)) inline void pvm_profile_end(void) {
    /* Every diagnostic invocation stops, dumps and resets exactly once on a normal typed return. */
    pvm_profile_pause();
    pvm_profile_flush();
}
#endif
