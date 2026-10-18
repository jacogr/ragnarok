// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

/* Non-LTO observation/timing only; no protocol, crypto, allocator or application logic. */
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
/* Opaque memory clobber preserves complete externally visible operation results without modifying them. */
void rb_observe(const void *data, size_t size) {
    __asm__ volatile("" : : "r"(data), "r"(size) : "memory");
}
/* The Python harness supplies trusted bounded controls; native code validates them again before use. */
int rb_control(int which) {
    const char *value = getenv(which ? "RAGNAROK_BENCH_ITERATIONS" : "RAGNAROK_BENCH_CASE");
    return value ? atoi(value) : 0;
}
/* Use the same OS nanosecond monotonic clock in both compiler runtimes. */
uint64_t rb_now_ns(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value)) abort(); /* Never accept a failed clock as timing evidence. */
    return (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
}
