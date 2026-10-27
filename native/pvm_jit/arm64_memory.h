/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Local ARM64 experiment: bounded executable storage only; all PVM semantics stay in Nim.
 */
#ifndef RAGNAROK_ARM64_JIT_MEMORY_H
#define RAGNAROK_ARM64_JIT_MEMORY_H
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
/* Process CPU clocks keep compiler/publication timing separate from execution. */
static uint64_t pvm_arm64_jit_cpu_ns(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &now) != 0) abort();
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}
#if defined(__APPLE__) && defined(__aarch64__)
#include <sys/mman.h>
#include <pthread.h>
#include <libkern/OSCacheControl.h>
#endif
/* Each exclusive arena owns one fixed mapping. Published fragments are never overwritten. */
typedef struct { void *memory; uint32_t used; uint32_t capacity; } pvm_arm64_arena;
static void *pvm_arm64_arena_create(void) {
#if defined(__APPLE__) && defined(__aarch64__)
    const uint32_t capacity = 1024 * 1024;
    pvm_arm64_arena *owner = calloc(1, sizeof(*owner));
    if (!owner) return NULL;
    owner->memory = mmap(NULL, capacity, PROT_READ | PROT_WRITE | PROT_EXEC,
                        MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (owner->memory == MAP_FAILED) { free(owner); return NULL; }
    owner->capacity = capacity;
    pthread_jit_write_protect_np(1);
    return owner;
#else
    /* Unsupported platforms refuse before allocation or execution. */
    return NULL;
#endif
}
static void pvm_arm64_arena_destroy(void *handle) {
    if (!handle) return;
#if defined(__APPLE__) && defined(__aarch64__)
    pvm_arm64_arena *owner = handle;
    munmap(owner->memory, owner->capacity);
#endif
    free(handle);
}
static int32_t pvm_arm64_arena_publish(void *handle, const uint32_t *words, uint32_t count) {
#if defined(__APPLE__) && defined(__aarch64__)
    pvm_arm64_arena *owner = handle;
    if (!owner || !words || count == 0 || count > 1024) return -1;
    uint32_t length = count * 4;
    if (owner->used > owner->capacity || length > owner->capacity - owner->used) return -1;
    uint32_t offset = owner->used;
    pthread_jit_write_protect_np(0);
    memcpy((unsigned char *)owner->memory + offset, words, length);
    sys_icache_invalidate((unsigned char *)owner->memory + offset, length);
    pthread_jit_write_protect_np(1);
    owner->used += length;
    return (int32_t)offset;
#else
    (void)handle; (void)words; (void)count;
    return -1;
#endif
}
static int pvm_arm64_arena_call(void *handle, uint32_t offset, void *registers) {
#if defined(__APPLE__) && defined(__aarch64__)
    pvm_arm64_arena *owner = handle;
    if (!owner || !registers || offset >= owner->used || (offset & 3)) return 0;
    void (*entry)(void *) = (void (*)(void *))((unsigned char *)owner->memory + offset);
    entry(registers);
    return 1;
#else
    (void)handle; (void)offset; (void)registers;
    return 0;
#endif
}
/* Conditional leaves return only a previously validated scalar stream offset, never a host address. */
static uint32_t pvm_arm64_arena_next(void *handle, uint32_t offset, void *registers) {
#if defined(__APPLE__) && defined(__aarch64__)
    pvm_arm64_arena *owner = handle;
    if (!owner || !registers || offset >= owner->used || (offset & 3)) return UINT32_MAX;
    uint32_t (*entry)(void *) = (uint32_t (*)(void *))((unsigned char *)owner->memory + offset);
    return entry(registers);
#else
    (void)handle; (void)offset; (void)registers;
    return UINT32_MAX;
#endif
}

#endif
