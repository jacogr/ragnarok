/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Read the process CPU clock using the OS constant from its system header.
 */
#ifndef RAGNAROK_PVM_SIEVE_CLOCK_H
#define RAGNAROK_PVM_SIEVE_CLOCK_H
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

/* Fail closed if process CPU accounting is unavailable; never emit a fake duration. */
static int64_t pvm_sieve_cpu_nanoseconds(void) {
    struct timespec value = {0, 0};
    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &value) != 0) {
        abort();
    }
    if (value.tv_sec < 0 || value.tv_nsec < 0 || value.tv_nsec >= 1000000000 ||
        value.tv_sec > (INT64_MAX - value.tv_nsec) / INT64_C(1000000000)) {
        abort();
    }
    return (int64_t)value.tv_sec * INT64_C(1000000000) + value.tv_nsec;
}
#endif
