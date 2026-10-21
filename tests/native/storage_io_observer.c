/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0 */

/* Single-threaded test-only injected OS refusals retain real IO on every uninjected operation.
 * This object is compiled without redirect.h; it never changes production or SDK implementation. */
#include "observer.h"
#include <errno.h>
#include <limits.h>
#include <unistd.h>

/* Bounded scalar configuration performs no allocation or logging at an observed call boundary. */
static int selected, skipped, remaining, reason;
static uint64_t calls[4];
static size_t write_limit;

void storage_io_reset(void) {
    /* Reset every configured fault/short-write cap before unrelated fixture or runner IO. */
    selected = skipped = remaining = reason = 0;
    write_limit = 0;
    for (int index = 0; index < 4; index++) {
        /* Each known operation begins with an independently observable zero count. */
        calls[index] = 0;
    }
}
int storage_io_arm(int operation, int skip, int failures, int error) {
    /* Invalid controls cannot index the private observer array or select unspecified behavior. */
    if (operation < STORAGE_IO_READ || operation > STORAGE_IO_FSYNC || skip < 0 || failures < 0) {
        /* Refuse invalid indexing and signed countdowns before changing any controls. */
        return -1;
    }
    selected = operation;
    skipped = skip;
    remaining = failures;
    reason = error;
    return 0;
}
uint64_t storage_io_calls(int operation) {
    /* Invalid query IDs are inert; tests additionally require their chosen operation to execute. */
    if (operation < STORAGE_IO_READ || operation > STORAGE_IO_FSYNC) {
        /* Unknown operations expose no counter or mutable observer storage. */
        return 0;
    }
    return calls[operation];
}
int storage_io_remaining(void) {
    /* A consumed-fault assertion prevents an unexecuted injected branch from passing a test. */
    return remaining;
}
void storage_io_write_limit(size_t limit) {
    /* Optional real short writes exercise progress followed by interruption; zero removes the cap. */
    write_limit = limit;
}
static int refuse(int operation) {
    /* Saturating diagnostic counters avoid signed arithmetic overflow in the test observer itself. */
    if (calls[operation] != UINT64_MAX) {
        /* Retain diagnostic monotonicity without unsigned wraparound. */
        calls[operation]++;
    }
    if (operation != selected || remaining == 0) {
        /* Unarmed or exhausted fault configurations always forward the actual SDK call. */
        return 0;
    }
    if (skipped > 0) {
        /* Advance through genuine calls until the requested refusal boundary. */
        skipped--;
        return 0;
    }
    remaining--;
    errno = reason;
    return 1;
}
ssize_t storage_io_read(int descriptor, void *buffer, size_t count) {
    /* A refused read transfers no bytes; every positive control uses the actual descriptor. */
    if (refuse(STORAGE_IO_READ)) {
        /* A rejected read must not modify caller bytes or fabricate progress. */
        return -1;
    }
    return read(descriptor, buffer, count);
}
ssize_t storage_io_write(int descriptor, const void *buffer, size_t count) {
    /* Positive short writes are genuine OS writes, not fabricated progress receipts. */
    if (refuse(STORAGE_IO_WRITE)) {
        /* Rejected writes retain errno and transfer no caller bytes. */
        return -1;
    }
    if (write_limit != 0 && count > write_limit) {
        /* Only actual native positive results can authorize caller offset advancement. */
        count = write_limit;
    }
    return write(descriptor, buffer, count);
}
int storage_io_fsync(int descriptor) {
    /* All successful barriers call the SDK; injection models syscall refusal, not physical power loss. */
    if (refuse(STORAGE_IO_FSYNC)) {
        /* An injected refusal must never become a successful durability receipt. */
        return -1;
    }
    return fsync(descriptor);
}
