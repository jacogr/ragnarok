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
#include <sys/stat.h>
#include <signal.h>
#include <time.h>
#include <sys/wait.h>

/* Bounded scalar configuration performs no allocation or logging at an observed call boundary. */
static int selected, skipped, remaining, reason;
static uint64_t calls[STORAGE_IO_LAST+1];
static size_t write_limit, read_limit;
static int reuse_close, reused_descriptor = -1;
static int zero_skip, zero_remaining;
/* A single-threaded fixture retains ownership; the controller checks identity before its one write. */
static int growth_descriptor = -1, growth_pending;
static off_t growth_extent;
/* Shrink fixtures retain a separate exact descriptor and cannot overlap a pending extent change. */
static int shrink_descriptor = -1, shrink_pending;
static off_t shrink_extent;
static dev_t shrink_device;
static ino_t shrink_inode;
static dev_t growth_device;
static ino_t growth_inode;



/* Each process owns one pipe end; only the parent owns and reaps the exact positive child PID. */
static pid_t crash_child = -1;
static int crash_reader = -1, crash_writer = -1;
static int crash_operation, crash_skip, crash_started, crash_ready;
static uint64_t crash_completed, crash_observed;
struct crash_event {
    uint64_t magic, count;
    int operation, stopped;
};
#define CRASH_MAGIC UINT64_C(0x53544f5243524153)

static void crash_close_pipe(void) {
    /* Retire each test-owned endpoint once; never retry a potentially reused descriptor. */
    if (crash_reader >= 0) {
        close(crash_reader);
        crash_reader = -1;
    }
    if (crash_writer >= 0) {
        close(crash_writer);
        crash_writer = -1;
    }
}
static int crash_send(int stopped) {
    /* One local fixed-size receipt fits PIPE_BUF and never grants storage or protocol authority. */
    struct crash_event event = {CRASH_MAGIC, crash_completed, crash_operation, stopped};
    ssize_t amount;
    do {
        amount = write(crash_writer, &event, sizeof(event));
    } while (amount < 0 && errno == EINTR);
    return amount == (ssize_t)sizeof(event);
}
static void crash_after(int operation) {
    /* Only completed real SDK operations can witness a stop; injected refusal never reaches here. */
    if (crash_started && operation == crash_operation) {
        crash_completed++;
        if (crash_completed == (uint64_t)crash_skip + 1) {
            /* Publish the exact selected boundary before the kernel reports the child stopped. */
            if (!crash_send(1)) {
                _exit(120);
            }
            raise(SIGSTOP);
            _exit(121); /* A resumed child must never continue the storage operation or run destructors. */
        }
    }
}
int storage_io_crash_fork(int operation, int skip) {
    /* Validate bounded controls before allocating a pipe or replacing any existing child ownership. */
    if (operation < STORAGE_IO_READ || operation > STORAGE_IO_LAST || skip < 0 || skip > 4096 ||
        crash_child > 0 || crash_writer >= 0 || crash_reader >= 0) {
        return -1;
    }
    int descriptors[2];
    if (pipe(descriptors) != 0) {
        return -1;
    }
    int flags = fcntl(descriptors[0], F_GETFL);
    if (flags < 0 || fcntl(descriptors[0], F_SETFL, flags | O_NONBLOCK) < 0) {
        close(descriptors[0]);
        close(descriptors[1]);
        return -1;
    }
    pid_t child = fork();
    if (child < 0) {
        close(descriptors[0]);
        close(descriptors[1]);
        return -1;
    }
    crash_operation = operation;
    crash_skip = skip;
    crash_started = crash_ready = 0;
    crash_completed = crash_observed = 0;
    if (child == 0) {
        /* Child setup is intentionally outside the observed window until its explicit start. */
        close(descriptors[0]);
        crash_writer = descriptors[1];
        crash_child = -1;
    } else {
        /* The original process retains only its exact child and a nonblocking receipt endpoint. */
        close(descriptors[1]);
        crash_reader = descriptors[0];
        crash_child = child;
    }
    return (int)child;
}
int storage_io_crash_start(void) {
    /* A parent or an already armed child cannot silently alter the selected boundary. */
    if (crash_writer < 0 || crash_started) {
        return -1;
    }
    crash_started = 1;
    crash_completed = 0;
    return 0;
}
void storage_io_crash_exit(int status) {
    /* Explicit successful completion is a baseline receipt, never a passing crash receipt. */
    if (crash_writer >= 0 && status == 0 && !crash_send(0)) {
        _exit(122);
    }
    _exit(status);
}
uint64_t storage_io_crash_count(void) {
    /* The parent exposes only a fully checked receipt's completed-operation count. */
    return crash_observed;
}
static int crash_clock(uint64_t *milliseconds) {
    /* A monotonic elapsed deadline is independent from wall-clock corrections. */
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        return 0;
    }
    *milliseconds = (uint64_t)now.tv_sec * 1000 + (uint64_t)now.tv_nsec / 1000000;
    return 1;
}
static int crash_reap(void) {
    /* A bounded second wait verifies SIGKILL termination of this exact child, including timeout cleanup. */
    uint64_t start = 0, now = 0;
    if (kill(crash_child, SIGKILL) != 0 && errno != ESRCH) {
        return 0;
    }
    if (!crash_clock(&start)) {
        return 0;
    }
    do {
        int status = 0;
        pid_t seen = waitpid(crash_child, &status, WNOHANG);
        if (seen == crash_child) {
            crash_child = -1;
            return WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL;
        }
        if (seen < 0 && errno != EINTR) {
            /* ECHILD retires ownership: its old PID must never be signaled again. */
            if (errno == ECHILD) {
                crash_child = -1;
            }
            return 0;
        }
        struct timespec pause = {0, 1000000};
        nanosleep(&pause, NULL);
        if (!crash_clock(&now)) {
            return 0;
        }
    } while (now - start < 10000);
    return 0;
}
static int crash_wait(int timeout_ms) {
    /* Missing, late or malformed witnesses cannot become a successful crash qualification. */
    if (crash_child <= 0 || timeout_ms < 1 || timeout_ms > 30000) {
        return STORAGE_CRASH_INVALID;
    }
    if (crash_ready) {
        /* A verified stop is retained only until explicit finish/abort; receipt bytes are consumed once. */
        return STORAGE_CRASH_KILLED;
    }
    uint64_t start = 0, now = 0;
    int verdict = STORAGE_CRASH_ERROR;
    if (crash_clock(&start)) {
        do {
            int status = 0;
            pid_t seen = waitpid(crash_child, &status, WNOHANG | WUNTRACED);
            if (seen == crash_child) {
                struct crash_event event = {0, 0, 0, 0};
                ssize_t amount = read(crash_reader, &event, sizeof(event));
                int valid = amount == (ssize_t)sizeof(event) && event.magic == CRASH_MAGIC &&
                    event.operation == crash_operation;
                if (WIFSTOPPED(status)) {
                    /* An unrelated SIGSTOP without the exact syscall receipt is a failed witness. */
                    if (WSTOPSIG(status) == SIGSTOP && valid && event.stopped == 1 &&
                        event.count == (uint64_t)crash_skip + 1) {
                        crash_observed = event.count;
                        verdict = STORAGE_CRASH_KILLED;
                    } else {
                        verdict = STORAGE_CRASH_INVALID;
                    }
                } else {
                    crash_child = -1; /* waitpid already reaped an exited or independently signaled child. */
                    if (WIFEXITED(status) && WEXITSTATUS(status) == 0 && valid && event.stopped == 0) {
                        crash_observed = event.count;
                        verdict = STORAGE_CRASH_COMPLETED;
                    }
                }
                break;
            }
            if (seen < 0 && errno != EINTR) {
                /* A reaped child no longer grants ownership of its potentially reused PID. */
                if (errno == ECHILD) {
                    crash_child = -1;
                }
                break;
            }
            struct timespec pause = {0, 1000000};
            nanosleep(&pause, NULL);
            if (!crash_clock(&now)) {
                break;
            }
            if (now - start >= (uint64_t)timeout_ms) {
                verdict = STORAGE_CRASH_TIMEOUT;
                break;
            }
        } while (1);
    }
    if (verdict == STORAGE_CRASH_KILLED && crash_child > 0) {
        /* Keep the exact stopped child and its lease alive for the parent's contention witness. */
        crash_ready = 1;
        return verdict;
    }
    if (crash_child > 0 && !crash_reap()) {
        verdict = STORAGE_CRASH_ERROR;
    }
    crash_close_pipe();
    return verdict;
}
int storage_io_crash_wait(int timeout_ms) {
    /* A stopped witness is not a killed witness; callers must explicitly finish or abort ownership. */
    int verdict = crash_wait(timeout_ms);
    return verdict == STORAGE_CRASH_KILLED ? STORAGE_CRASH_STOPPED : verdict;
}
int storage_io_crash_finish(int timeout_ms) {
    /* Preserve the original finish contract: success still requires exact SIGKILL termination and reap. */
    int verdict = crash_wait(timeout_ms);
    if (verdict == STORAGE_CRASH_KILLED) {
        int killed = crash_reap();
        crash_ready = 0;
        crash_close_pipe();
        return killed ? STORAGE_CRASH_KILLED : STORAGE_CRASH_ERROR;
    }
    return verdict;
}
void storage_io_crash_abort(void) {
    /* Parent failure paths still kill/reap only their owned child; the receipt can never claim success. */
    crash_ready = 0;
    if (crash_child > 0) {
        (void)crash_reap();
    }
    crash_close_pipe();
}

void storage_io_reset(void) {
    /* Reset every configured fault/short-write cap before unrelated fixture or runner IO. */
    /* The controller owns only its explicitly created replacement, never an application descriptor. */
    if (reused_descriptor >= 0) {
        close(reused_descriptor);
        reused_descriptor = -1;
    }
    reuse_close = 0;
    selected = skipped = remaining = reason = 0;
    write_limit = read_limit = 0;
    zero_skip = zero_remaining = 0;
    /* Forget the borrowed fixture descriptor without closing or otherwise transferring its ownership. */
    growth_descriptor = -1;
    growth_pending = 0;
    shrink_descriptor = -1;
    shrink_pending = 0;
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
void storage_io_read_limit(size_t limit) {
    /* Genuine reads may stop short; zero disables the cap without changing EOF semantics. */
    read_limit = limit;
}
int storage_io_grow_on_read(int descriptor, int64_t extent) {
    /* Refuse invalid, shrinking, excessive or replacement controls before touching active state. */
    struct stat metadata;
    int flags = descriptor < 0 ? -1 : fcntl(descriptor, F_GETFL);
    if (flags < 0 || (flags & O_ACCMODE) == O_RDONLY ||
        descriptor < 0 || extent < 0 || extent > 65536 || growth_pending || shrink_pending ||
        fstat(descriptor, &metadata) != 0 || !S_ISREG(metadata.st_mode) ||
        metadata.st_size < 0 || metadata.st_size >= extent) {
        return -1;
    }
    growth_descriptor = descriptor;
    growth_extent = (off_t)extent;
    growth_device = metadata.st_dev;
    growth_inode = metadata.st_ino;
    growth_pending = 1;
    return 0;
}
int storage_io_shrink_on_read(int descriptor, int64_t extent) {
    /* Validate every scalar, permission and inode bound before replacing active fixture state. */
    struct stat metadata;
    int flags = descriptor < 0 ? -1 : fcntl(descriptor, F_GETFL);
    if (flags < 0 || (flags & O_ACCMODE) == O_RDONLY || extent < 0 ||
        extent > 65536 || growth_pending || shrink_pending ||
        fstat(descriptor, &metadata) != 0 || !S_ISREG(metadata.st_mode) ||
        metadata.st_size <= extent || metadata.st_size > 65536) {
        return -1;
    }
    shrink_descriptor = descriptor;
    shrink_extent = (off_t)extent;
    shrink_device = metadata.st_dev;
    shrink_inode = metadata.st_ino;
    shrink_pending = 1;
    return 0;
}
int storage_io_shrink_pending(void) {
    /* Positive consumption proves the fixture reached an actual native read boundary. */
    return shrink_pending;
}
int storage_io_growth_pending(void) {
    /* A one-shot pending flag distinguishes an executed growth from a skipped read path. */
    return growth_pending;
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
    if (growth_pending) {
        /* The reader has completed its stat; extend only the exact separately owned fixture inode. */
        struct stat metadata;
        int owned = growth_descriptor;
        growth_descriptor = -1;
        growth_pending = 0;
        if (fstat(owned, &metadata) != 0 || metadata.st_dev != growth_device ||
            metadata.st_ino != growth_inode || metadata.st_size < 0 ||
            metadata.st_size > growth_extent) {
            errno = EINVAL;
            return -1;
        }
        if (ftruncate(owned, growth_extent) != 0) {
            /* Failed real fixture IO supplies no positive read progress or growth claim. */
            return -1;
        }
    }
    if (shrink_pending) {
        /* Retire the one-shot control first; a reused descriptor must never truncate another inode. */
        struct stat metadata;
        int owned = shrink_descriptor;
        shrink_descriptor = -1;
        shrink_pending = 0;
        if (fstat(owned, &metadata) != 0 || metadata.st_dev != shrink_device ||
            metadata.st_ino != shrink_inode || metadata.st_size < shrink_extent ||
            metadata.st_size > 65536) {
            errno = EINVAL;
            return -1;
        }
        if (ftruncate(owned, shrink_extent) != 0) {
            /* A failed genuine truncation supplies no read bytes or success witness. */
            return -1;
        }
    }
    if (read_limit != 0 && count > read_limit) {
        /* Only actual positive kernel results advance the caller-owned byte extent. */
        count = read_limit;
    }
    ssize_t status = read(descriptor, buffer, count);
    if (status >= 0) {
        /* Stop only after a genuine successful OS operation, before the caller receives its result. */
        crash_after(STORAGE_IO_READ);
    }
    return status;
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
    ssize_t status = write(descriptor, buffer, count);
    if (status > 0) {
        /* Stop only after a genuine successful OS operation, before the caller receives its result. */
        crash_after(STORAGE_IO_WRITE);
    }
    return status;
}
int storage_io_fsync(int descriptor) {
    /* All successful barriers call the SDK; injection models syscall refusal, not physical power loss. */
    if (refuse(STORAGE_IO_FSYNC)) {
        /* An injected refusal must never become a successful durability receipt. */
        return -1;
    }
    int status = fsync(descriptor);
    if (status == 0) {
        /* Stop only after a genuine successful OS operation, before the caller receives its result. */
        crash_after(STORAGE_IO_FSYNC);
    }
    return status;
}
int storage_io_ftruncate(int descriptor, off_t extent) {
    /* Refusal does not select a prefix or mutate bytes; the caller supplies the already trusted extent. */
    if (refuse(STORAGE_IO_FTRUNCATE)) {
        return -1;
    }
    int status = ftruncate(descriptor, extent);
    if (status == 0) {
        /* Stop only after a genuine successful OS operation, before the caller receives its result. */
        crash_after(STORAGE_IO_FTRUNCATE);
    }
    return status;
}
int storage_io_flock(int descriptor, int operation) {
    /* Uninjected calls preserve the real cooperative nonblocking lease, including actual competition. */
    if (refuse(STORAGE_IO_FLOCK)) {
        return -1;
    }
    int status = flock(descriptor, operation);
    if (status == 0) {
        /* Stop only after a genuine successful OS operation, before the caller receives its result. */
        crash_after(STORAGE_IO_FLOCK);
    }
    return status;
}
int storage_io_renameat(int source_directory, const char *source, int target_directory, const char *target) {
    /* Only selected refusal bypasses the actual descriptor-relative SDK operation. */
    if (refuse(STORAGE_IO_RENAMEAT)) {
        return -1;
    }
    int status = renameat(source_directory, source, target_directory, target);
    if (status == 0) {
        /* Stop only after a genuine successful OS operation, before the caller receives its result. */
        crash_after(STORAGE_IO_RENAMEAT);
    }
    return status;
}
int storage_io_unlinkat(int directory, const char *path, int flags) {
    /* Only selected refusal bypasses the actual descriptor-relative SDK operation. */
    if (refuse(STORAGE_IO_UNLINKAT)) {
        return -1;
    }
    int status = unlinkat(directory, path, flags);
    if (status == 0) {
        /* Stop only after a genuine successful OS operation, before the caller receives its result. */
        crash_after(STORAGE_IO_UNLINKAT);
    }
    return status;
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
    int status = close(descriptor);
    if (status == 0) {
        /* Stop only after a genuine successful OS operation, before the caller receives its result. */
        crash_after(STORAGE_IO_CLOSE);
    }
    return status;
}
