/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0 */

/* Run bounded interpreter test inputs after normal Nimony startup and preserve the current case even when a native assertion exits directly. */
#define _GNU_SOURCE 1
#include "fuzz_driver.h"
#include <errno.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

/* The public driver copies its argument strings; the borrowed original storage outlives the joined child. */
extern int LLVMFuzzerRunDriver(int *, char ***, int (*)(const uint8_t *, size_t));
extern int LLVMFuzzerTestOneInput(const uint8_t *, size_t);

typedef struct {
    /* Only the child writes; the parent reads after join and acquire, with no shared Nim/ARC objects. */
    _Atomic unsigned ready;
    size_t size;
    uint8_t bytes[1024];
} CurrentInput;
static CurrentInput *current_input = NULL;

static int evaluate(const uint8_t *data, size_t size) {
    /* Snapshot only the admitted bytes before entering the interpreter test; empty input requires no readable source pointer. */
    if (size > sizeof(current_input->bytes)) return 0;
    atomic_store_explicit(&current_input->ready, 0, memory_order_release);
    if (size != 0) memcpy(current_input->bytes, data, size);
    current_input->size = size;
    atomic_store_explicit(&current_input->ready, 1, memory_order_release);
    return LLVMFuzzerTestOneInput(data, size);
}

static void save_case(const char *artifacts) {
    /* The invocation owns this private directory; exclusive creation preserves an existing result and refuses path aliases. */
    static const char prefix[] = "-artifact_prefix=";
    char path[4096];
    if (strncmp(artifacts, prefix, sizeof(prefix)-1) != 0) return;
    int length = snprintf(path, sizeof(path), "%scrash-native-exit", artifacts+sizeof(prefix)-1);
    if (length < 0 || (size_t)length >= sizeof(path)) return;
    int file = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (file < 0) return;
    size_t written = 0;
    while (written < current_input->size) {
        /* A partial or interrupted write never advances beyond the exact callback extent. */
        ssize_t count = write(file, current_input->bytes+written, current_input->size-written);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        written += (size_t)count;
    }
    int closed = close(file);
    if (written == current_input->size && closed == 0) {
        fprintf(stderr, "Saved current interpreter test case: %s\n", path);
        fflush(stderr);
    }
}

int ragnarok_fuzz_run(const char *corpus, const char *runs, const char *artifacts) {
    /* One bounded test child preserves ordinary Nimony exits without runtime hooks; neither process shares a mutable ARC graph. */
    void *mapping = mmap(NULL, sizeof(CurrentInput), PROT_READ | PROT_WRITE,
                         MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if (mapping == MAP_FAILED) return 2;
    current_input = mapping;
    atomic_init(&current_input->ready, 0);
    current_input->size = 0;
    pid_t child = fork();
    if (child < 0) {
        munmap(mapping, sizeof(CurrentInput));
        current_input = NULL;
        return 2;
    }
    if (child == 0) {
        /* Finite single-process coverage work uses fixed limits; original argument buffers remain unchanged in the parent. */
        char *arguments[] = {"ragnarok-pvm-program", (char *)runs, "-max_len=1024",
                            "-timeout=2", "-rss_limit_mb=1024", "-seed=1",
                            (char *)artifacts, (char *)corpus, NULL};
        char **argv = arguments;
        int argc = 8;
        int result = LLVMFuzzerRunDriver(&argc, &argv, evaluate);
        _exit(result == 0 ? 0 : 1);
    }
    int status = 0;
    pid_t joined;
    do {
        joined = waitpid(child, &status, 0);
    } while (joined < 0 && errno == EINTR); /* Interrupted joins never retire the admitted input early. */
    int result = 2;
    if (joined == child) {
        result = WIFEXITED(status) ? WEXITSTATUS(status) : 128+WTERMSIG(status);
        if (result != 0 && atomic_load_explicit(&current_input->ready, memory_order_acquire) &&
            current_input->size <= sizeof(current_input->bytes)) save_case(artifacts);
    }
    if (joined < 0 && errno != ECHILD) {
        /* Retire only our known child before releasing its shared input record on an unexpected join failure. */
        kill(child, SIGKILL);
        do {
            joined = waitpid(child, &status, 0);
        } while (joined < 0 && errno == EINTR);
    }
    munmap(mapping, sizeof(CurrentInput));
    current_input = NULL;
    return result;
}
