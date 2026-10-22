/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0 */

/* Test-only OS call observation forwards real descriptors unless explicitly armed. */
#ifndef RAGNAROK_STORAGE_IO_OBSERVER_H
#define RAGNAROK_STORAGE_IO_OBSERVER_H
#include <stdint.h>
#include <sys/types.h>
#include <stddef.h>
/* Exact observer operations are separate from production storage error domains. */
enum { STORAGE_IO_READ = 1, STORAGE_IO_WRITE = 2, STORAGE_IO_FSYNC = 3, STORAGE_IO_FTRUNCATE = 4,
       STORAGE_IO_FLOCK = 5, STORAGE_IO_RENAMEAT = 6, STORAGE_IO_UNLINKAT = 7, STORAGE_IO_LAST = STORAGE_IO_UNLINKAT };
/* Remove all fault/short-write controls and reset call counters. */
void storage_io_reset(void);
/* Select a bounded count of failures after a bounded number of real calls. */
int storage_io_arm(int operation, int skip, int failures, int reason);
/* Observe a saturating count without allocating or performing IO. */
uint64_t storage_io_calls(int operation);
/* Require planned faults to be consumed before accepting a test. */
int storage_io_remaining(void);
/* Cap genuine forwarded write progress; zero disables the cap. */
void storage_io_write_limit(size_t limit);
/* Produce bounded zero-progress write receipts after genuine calls; reject negative controls. */
int storage_io_zero_writes(int skip, int count);
/* Expose remaining zero-progress controls so unexercised paths cannot pass. */
int storage_io_zero_remaining(void);
/* Forward real SDK reads except explicitly selected test refusals. */
ssize_t storage_io_read(int descriptor, void *buffer, size_t count);
/* Forward real SDK writes with optional real short progress. */
ssize_t storage_io_write(int descriptor, const void *buffer, size_t count);
/* Forward actual barriers except explicitly selected test refusals. */
int storage_io_fsync(int descriptor);
/* Forward actual trusted-extent truncation except bounded injected refusals. */
int storage_io_ftruncate(int descriptor, off_t extent);
/* Forward actual nonblocking lease and unlock operations except selected test refusals. */
int storage_io_flock(int descriptor, int operation);
/* Observe namespace refusal without changing selected bytes. */
int storage_io_renameat(int source_directory, const char *source, int target_directory, const char *target);
/* Observe namespace refusal without changing selected bytes. */
int storage_io_unlinkat(int directory, const char *path, int flags);
#endif
