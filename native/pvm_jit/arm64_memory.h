/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Local ARM64 experiment: bounded executable storage only; all PVM semantics stay in Nim.
 */
#ifndef RAGNAROK_ARM64_JIT_MEMORY_H
#define RAGNAROK_ARM64_JIT_MEMORY_H
#include <stdint.h>
#include <stdlib.h>
#include "arena_retirement.h"
#include <string.h>
#include <time.h>
/* Process CPU clocks keep compiler/publication timing separate from execution. */
static uint64_t pvm_arm64_jit_cpu_ns(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &now) != 0) return 0;
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}
#if defined(__APPLE__) && defined(__aarch64__)
#include <sys/mman.h>
#include <pthread.h>
#include <libkern/OSCacheControl.h>
#endif
#if defined(__linux__) && defined(__aarch64__)
#include <sys/mman.h>
#include <unistd.h>
#include <linux/memfd.h>
/* GNU libc exposes this OS interface under feature macros that may precede generated includes. */
extern int memfd_create(const char *name, unsigned int flags);
#endif
#if defined(__aarch64__) && (defined(__APPLE__) || defined(__linux__))
#define PVM_ARM64_JIT_HOST 1
#else
#define PVM_ARM64_JIT_HOST 0
#endif
/* Each arena embeds its cleanup record before acquiring either OS alias. */
typedef struct {
    pvm_arena_retirement_owner retirement;
    void *memory; void *writable; uint32_t used; uint32_t capacity; unsigned mapped;
} pvm_arm64_arena;
_Static_assert(offsetof(pvm_arm64_arena, retirement) == 0, "arena cleanup prefix");
#ifdef PVM_NATIVE_RETIREMENT_WITNESS
#include <errno.h>
static void pvm_arm64_arena_refuse_unmaps(void *handle, unsigned count) {
    /* The generic owner remains live through a refused physical release. */
    if (handle) pvm_arena_refuse_unmaps(&((pvm_arm64_arena *)handle)->retirement, count);
}
#endif
#if PVM_ARM64_JIT_HOST
static int pvm_arm64_arena_unmap(pvm_arm64_arena *owner, void *address, size_t bytes) {
#ifdef PVM_NATIVE_RETIREMENT_WITNESS
    if (owner->retirement.unmaps_before_refusal) {
        owner->retirement.unmaps_before_refusal--;
    } else if (owner->retirement.refused_unmaps) {
        owner->retirement.refused_unmaps--;
        errno = EBUSY;
        return -1;
    }
#else
    (void)owner;
#endif
    return munmap(address, bytes);
}
#endif
static int pvm_arm64_arena_release_locked(pvm_arena_retirement_owner *record) {
    /* Static prefix layout binds this callback to the exact original arena and alias flags. */
    pvm_arm64_arena *owner = (pvm_arm64_arena *)record;
#if PVM_ARM64_JIT_HOST
    if ((owner->mapped & 1) && (!(owner->mapped & 2) || owner->writable != owner->memory)) {
        if (pvm_arm64_arena_unmap(owner, owner->writable, owner->capacity) != 0) return 0;
        owner->mapped &= ~1u;
        owner->writable = NULL;
    }
    if (owner->mapped & 2) {
        int shared = (owner->mapped & 1) && owner->writable == owner->memory;
        if (pvm_arm64_arena_unmap(owner, owner->memory, owner->capacity) != 0) return 0;
        owner->mapped &= ~2u;
        owner->memory = NULL;
        if (shared) { owner->mapped &= ~1u; owner->writable = NULL; }
    }
#endif
    free(owner);
    return 1;
}
static inline int pvm_arm64_arena_try_destroy(void *handle) {
    /* The caller retains the handle on failure; publication and invocation stay disarmed. */
    return pvm_arena_try_release((pvm_arena_retirement_owner *)handle);
}
static void pvm_arm64_arena_destroy(void *handle) {
    /* Last-drop cannot return an error; its embedded record survives a failed OS release. */
    pvm_arena_drop((pvm_arena_retirement_owner *)handle);
}
static void *pvm_arm64_arena_create_owned(pvm_arena_retirement_state *state) {
    /* Return an owned, non-callable cleanup handle if acquisition failed after a mapping survived. */
    const uint16_t little_endian = 1;
    if (*(const unsigned char *)&little_endian != 1) return NULL;
#if PVM_ARM64_JIT_HOST
    const uint32_t capacity = 1024 * 1024;
    pvm_arena_lock(state);
    if (!pvm_arena_drain_locked(state)) { pvm_arena_unlock(state); return NULL; }
    pvm_arm64_arena *owner = calloc(1, sizeof(*owner));
    if (!owner) { pvm_arena_unlock(state); return NULL; }
    pvm_arena_retirement_init(&owner->retirement, state, pvm_arm64_arena_release_locked);
    owner->capacity = capacity;
#if defined(__APPLE__)
    owner->memory = mmap(NULL, capacity, PROT_READ | PROT_WRITE | PROT_EXEC,
                        MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (owner->memory == MAP_FAILED) { owner->memory = NULL; goto failed; }
    owner->writable = owner->memory;
    owner->mapped = 3;
    if (!owner->memory) goto failed;
    pthread_jit_write_protect_np(1);
#ifdef PVM_NATIVE_RETIREMENT_WITNESS
    if (pvm_arena_fail_acquisition_locked(&owner->retirement)) goto failed;
#endif
#else
    int descriptor = memfd_create("ragnarok-pvm-code", MFD_CLOEXEC);
    if (descriptor < 0) goto failed;
    if (ftruncate(descriptor, capacity) != 0) { close(descriptor); goto failed; }
    owner->writable = mmap(NULL, capacity, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
    if (owner->writable == MAP_FAILED) { owner->writable = NULL; close(descriptor); goto failed; }
    owner->mapped = 1;
    if (!owner->writable) { close(descriptor); goto failed; }
#ifdef PVM_NATIVE_RETIREMENT_WITNESS
    if (pvm_arena_fail_acquisition_locked(&owner->retirement)) { close(descriptor); goto failed; }
#endif
    owner->memory = mmap(NULL, capacity, PROT_READ | PROT_EXEC, MAP_SHARED, descriptor, 0);
    close(descriptor);
    if (owner->memory == MAP_FAILED) { owner->memory = NULL; goto failed; }
    owner->mapped |= 2;
    if (!owner->memory) goto failed;
#endif
    pvm_arena_unlock(state);
    return owner;
failed:
    owner->retirement.retiring = 1;
    if (pvm_arm64_arena_release_locked(&owner->retirement)) owner = NULL;
    pvm_arena_unlock(state);
    return owner;
#else
    (void)state;
    return NULL;
#endif
}
static void *pvm_arm64_arena_create(void) {
    /* Legacy direct owners receive callable arenas only; failed acquisition still retains cleanup. */
    pvm_arm64_arena *owner = pvm_arm64_arena_create_owned(pvm_arena_retirement_state_address());
    if (owner && owner->retirement.retiring) { pvm_arm64_arena_destroy(owner); return NULL; }
    return owner;
}
static int32_t pvm_arm64_arena_publish(void *handle, const uint32_t *words, uint32_t count) {
#if PVM_ARM64_JIT_HOST
    pvm_arm64_arena *owner = handle;
    if (!owner || owner->retirement.retiring || !words || count == 0 || count > 1024) return -1;
    uint32_t length = count * 4;
    if (owner->used > owner->capacity || length > owner->capacity - owner->used) return -1;
    uint32_t offset = owner->used;
#if defined(__APPLE__)
    pthread_jit_write_protect_np(0);
#endif
    memcpy((unsigned char *)owner->writable + offset, words, length);
#if defined(__APPLE__)
    sys_icache_invalidate((unsigned char *)owner->memory + offset, length);
    pthread_jit_write_protect_np(1);
#else
    /* Clean the written alias and invalidate the executable alias before publishing its offset. */
    __builtin___clear_cache((char *)owner->writable + offset, (char *)owner->writable + offset + length);
    __builtin___clear_cache((char *)owner->memory + offset, (char *)owner->memory + offset + length);
#endif
    owner->used += length;
    return (int32_t)offset;
#else
    (void)handle; (void)words; (void)count;
    return -1;
#endif
}
static int pvm_arm64_arena_call(void *handle, uint32_t offset, void *registers) {
#if PVM_ARM64_JIT_HOST
    pvm_arm64_arena *owner = handle;
    if (!owner || owner->retirement.retiring || !registers || offset >= owner->used || (offset & 3)) return 0;
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
#if PVM_ARM64_JIT_HOST
    pvm_arm64_arena *owner = handle;
    if (!owner || owner->retirement.retiring || !registers || offset >= owner->used || (offset & 3)) return UINT32_MAX;
    uint32_t (*entry)(void *) = (uint32_t (*)(void *))((unsigned char *)owner->memory + offset);
    return entry(registers);
#else
    (void)handle; (void)offset; (void)registers;
    return UINT32_MAX;
#endif
}

/* Connected leaves borrow a fresh scalar invocation context; no invocation address is retained. */
static uint32_t pvm_arm64_arena_region(void *handle, uint32_t offset, void *registers, void *state) {
#if PVM_ARM64_JIT_HOST
    pvm_arm64_arena *owner = handle;
    if (!owner || owner->retirement.retiring || !registers || !state || offset >= owner->used || (offset & 3)) return UINT32_MAX;
    uint32_t (*entry)(void *, void *) =
        (uint32_t (*)(void *, void *))((unsigned char *)owner->memory + offset);
    return entry(registers, state);
#else
    (void)handle; (void)offset; (void)registers; (void)state;
    return UINT32_MAX;
#endif
}

#endif
