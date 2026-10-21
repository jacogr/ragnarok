/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0 */

/* Single-threaded test-only injected OS refusals retain real IO on every uninjected operation.
 * This object is compiled without redirect.h; it never changes production or SDK implementation. */
#include "observer.h"
#include <errno.h>
#include <limits.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/file.h>

/* Bounded scalar configuration performs no allocation or logging at an observed call boundary. */
static int selected, skipped, remaining, reason;
static uint64_t calls[STORAGE_IO_LAST+1];
static size_t write_limit;
static int reuse_close, reused_descriptor = -1;
static int zero_skip, zero_remaining;

void storage_io_reset(void) {
    /* Reset every configured fault/short-write cap before unrelated fixture or runner IO. */
    /* The controller owns only its explicitly created replacement, never an application descriptor. */
    if (reused_descriptor >= 0) {
        close(reused_descriptor);
        reused_descriptor = -1;
    }
    reuse_close = 0;
    selected = skipped = remaining = reason = 0;
    write_limit = 0;
    zero_skip = zero_remaining = 0;
    for (int index = 0; index <= STORAGE_IO_LAST; index++) {
        /* Each known operation begins with an independently observable zero count. */
        calls[index] = 0;
    }
}
int storage_io_arm(int operation, int skip, int failures, int error) {
    /* Invalid controls cannot index the private observer array or select unspecified behavior. */
    if (operation < STORAGE_IO_READ || operation > STORAGE_IO_LAST || skip < 0 || failures < 0) {
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
    if (operation < STORAGE_IO_READ || operation > STORAGE_IO_LAST) {
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
int storage_io_zero_writes(int skip, int count) {
    /* Negative controls cannot create an unbounded countdown or mutate active configuration. */
    if (skip < 0 || count < 0) {
        return -1;
    }
    zero_skip = skip;
    zero_remaining = count;
    return 0;
}
int storage_io_zero_remaining(void) {
    /* Completion witnesses distinguish a real zero-progress refusal from an unexercised branch. */
    return zero_remaining;
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
    if (zero_remaining > 0) {
        /* Forward the chosen genuine prefix before producing an explicit no-progress receipt. */
        if (zero_skip > 0) {
            zero_skip--;
        } else {
            zero_remaining--;
            return 0;
        }
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
int storage_io_ftruncate(int descriptor, off_t extent) {
    /* Refusal does not select a prefix or mutate bytes; the caller supplies the already trusted extent. */
    if (refuse(STORAGE_IO_FTRUNCATE)) {
        return -1;
    }
    return ftruncate(descriptor, extent);
}
int storage_io_flock(int descriptor, int operation) {
    /* Uninjected calls preserve the real cooperative nonblocking lease, including actual competition. */
    if (refuse(STORAGE_IO_FLOCK)) {
        return -1;
    }
    return flock(descriptor, operation);
}
int storage_io_renameat(int source_directory, const char *source, int target_directory, const char *target) {
    /* Only selected refusal bypasses the actual descriptor-relative SDK operation. */
    if (refuse(STORAGE_IO_RENAMEAT)) {
        return -1;
    }
    return renameat(source_directory, source, target_directory, target);
}
int storage_io_unlinkat(int directory, const char *path, int flags) {
    /* Only selected refusal bypasses the actual descriptor-relative SDK operation. */
    if (refuse(STORAGE_IO_UNLINKAT)) {
        return -1;
    }
    return unlinkat(directory, path, flags);
}
void storage_io_reuse_close(void) {
    /* Enable one test-owned replacement immediately after an observed real descriptor retirement. */
    reuse_close = 1;
}
int storage_io_reused_open(void) {
    /* An accidental retry of the retired descriptor would destroy this independent resource. */
    return reused_descriptor >= 0 && fcntl(reused_descriptor, F_GETFD) >= 0;
}
int storage_io_close(int descriptor) {
    /* Model the allowed retired-before-error outcome; successful paths call the real SDK exactly once. */
    if (refuse(STORAGE_IO_CLOSE)) {
        int error = errno;
        if (close(descriptor) == 0 && reuse_close) {
            int replacement = open("/dev/null", O_RDONLY | O_CLOEXEC);
            if (replacement >= 0) {
                /* Place a separately owned resource at exactly the retired number before returning. */
                if (replacement == descriptor) {
                    reused_descriptor = replacement;
                } else {
                    if (dup2(replacement, descriptor) >= 0) {
                        reused_descriptor = descriptor;
                    }
                    close(replacement);
                }
            }
        }
        errno = error;
        return -1;
    }
    return close(descriptor);
}
