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
       STORAGE_IO_FLOCK = 5, STORAGE_IO_RENAMEAT = 6, STORAGE_IO_UNLINKAT = 7, STORAGE_IO_CLOSE = 8, STORAGE_IO_LAST = STORAGE_IO_CLOSE };
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
/* Cap actual read progress without fabricating bytes or EOF. */
void storage_io_read_limit(size_t limit);
/* Borrow an owned writable regular descriptor until reset or one read; grow at most64 KiB after stat. */
int storage_io_grow_on_read(int descriptor, int64_t extent);
/* Require the real read-boundary growth to execute before accepting its fixture. */
int storage_io_growth_pending(void);
/* One real post-stat truncation is limited to an already test-owned regular inode of at most64 KiB. */
int storage_io_shrink_on_read(int descriptor, int64_t extent);
int storage_io_shrink_pending(void);
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
/* Model close retiring a descriptor before reporting EINTR; never retry that number. */
int storage_io_close(int descriptor);
void storage_io_reuse_close(void);
int storage_io_reused_open(void);
/* Supervise one real process and distinguish witnessed SIGKILL from normal completion or failure. */
enum { STORAGE_CRASH_KILLED = 1, STORAGE_CRASH_COMPLETED = 2, STORAGE_CRASH_INVALID = 3,
       STORAGE_CRASH_TIMEOUT = 4, STORAGE_CRASH_ERROR = 5, STORAGE_CRASH_STOPPED = 6 };
int storage_io_crash_fork(int operation, int skip);
int storage_io_crash_start(void);
void storage_io_crash_exit(int status);
int storage_io_crash_finish(int timeout_ms);
/* Retain the verified stopped child so the parent can exercise real cross-process contention. */
int storage_io_crash_wait(int timeout_ms);
void storage_io_crash_abort(void);
uint64_t storage_io_crash_count(void);
#endif
