/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Sample the original Linux x86-64 benchmark text without recompiling it.
 * Process CPU clock events bind the sampled RIPs to its own reported calls.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <link.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <time.h>
#include <ucontext.h>
#include <unistd.h>

enum { sample_limit = 16384, clock_limit = 256 };
_Static_assert(ATOMIC_LONG_LOCK_FREE == 2, "Signal samples require lock-free x86-64 atomics");

struct observation {
    _Atomic uint64_t cpu;
    _Atomic uintptr_t pc;
};

static struct observation samples[sample_limit];
static uint64_t clocks[clock_limit];
static char mappings[65536];
static volatile sig_atomic_t sample_count;
static volatile sig_atomic_t dropped;
static size_t clock_count;
static size_t mappings_length;
static uintptr_t image_base;
static _Atomic long main_thread;
static const char *output_name;
static int (*real_clock)(clockid_t, struct timespec *);

static uint64_t cpu_time(const struct timespec *value) {
    return (uint64_t)value->tv_sec * UINT64_C(1000000000) + (uint64_t)value->tv_nsec;
}

/* Only the main guest thread contributes ticks. The handler neither allocates nor logs. */
static void record_pc(int number, siginfo_t *detail, void *context) {
    (void)number;
    (void)detail;
    int saved_errno = errno;
    if (syscall(SYS_gettid) == atomic_load_explicit(&main_thread, memory_order_relaxed)) {
        sig_atomic_t index = sample_count;
        if (index < sample_limit) {
            struct timespec now;
            if (syscall(SYS_clock_gettime, CLOCK_PROCESS_CPUTIME_ID, &now) == 0) {
                const ucontext_t *interrupted = context;
                atomic_store_explicit(&samples[index].cpu, cpu_time(&now), memory_order_relaxed);
                uintptr_t pc = (uintptr_t)interrupted->uc_mcontext.gregs[REG_RIP];
                atomic_store_explicit(&samples[index].pc, pc, memory_order_relaxed);
                sample_count = index + 1;
            }
        } else {
            dropped = 1;
        }
    }
    errno = saved_errno;
}

/* Interpose the canonical clock itself. The returned values remain the real process times. */
int clock_gettime(clockid_t clock, struct timespec *value) {
    int result = real_clock != NULL ? real_clock(clock, value) :
                 (int)syscall(SYS_clock_gettime, clock, value);
    if (result == 0 && output_name != NULL && clock == CLOCK_PROCESS_CPUTIME_ID &&
        syscall(SYS_gettid) == main_thread && clock_count < clock_limit) {
        clocks[clock_count++] = cpu_time(value);
        if (clock_count == 20) {
            /* Capture live mappings after JIT installation and before runtime retirement. */
            int saved_errno = errno;
            int fd = open("/proc/self/maps", O_RDONLY | O_CLOEXEC);
            if (fd >= 0) {
                for (;;) {
                    ssize_t count = read(fd, mappings + mappings_length,
                                         sizeof(mappings) - mappings_length);
                    if (count <= 0) break;
                    mappings_length += (size_t)count;
                }
                close(fd);
            }
            errno = saved_errno;
        }
    }
    return result;
}

static int find_main(struct dl_phdr_info *image, size_t size, void *opaque) {
    (void)size;
    (void)opaque;
    if (image->dlpi_name[0] != '\0') return 0;
    image_base = (uintptr_t)image->dlpi_addr;
    return 1;
}

/* Write a complete sample receipt only after stopping the timer. */
static void finish_sampling(void) {
    struct itimerval stop = {0};
    setitimer(ITIMER_PROF, &stop, NULL);
    FILE *output = fopen(output_name, "w");
    if (output == NULL) return;
    fprintf(output, "BASE,%" PRIxPTR "\nDROPPED,%d\n", image_base, (int)dropped);
    for (size_t i = 0; i < clock_count; ++i)
        fprintf(output, "CLOCK,%" PRIu64 "\n", clocks[i]);
    sig_atomic_t count = sample_count;
    for (sig_atomic_t i = 0; i < count; ++i)
        fprintf(output, "PC,%" PRIu64 ",%" PRIxPTR "\n",
                atomic_load_explicit(&samples[i].cpu, memory_order_relaxed),
                atomic_load_explicit(&samples[i].pc, memory_order_relaxed));
    fputs("MAPS\n", output);
    fwrite(mappings, 1, mappings_length, output);
    fclose(output);
}

__attribute__((constructor)) static void start_sampling(void) {
    const char *path = getenv("PVM_SIEVE_PC_LOG");
    if (path == NULL || path[0] == '\0') return;
    real_clock = dlsym(RTLD_NEXT, "clock_gettime");
    main_thread = syscall(SYS_gettid);
    dl_iterate_phdr(find_main, NULL);
    struct sigaction signal_action = {0};
    signal_action.sa_sigaction = record_pc;
    signal_action.sa_flags = SA_SIGINFO | SA_RESTART;
    sigemptyset(&signal_action.sa_mask);
    struct itimerval timer = {
        .it_interval = { .tv_usec = 1000 },
        .it_value = { .tv_usec = 1000 },
    };
    if (sigaction(SIGPROF, &signal_action, NULL) != 0 ||
        setitimer(ITIMER_PROF, &timer, NULL) != 0 ||
        atexit(finish_sampling) != 0) {
        _Exit(90);
    }
    output_name = path;
}
