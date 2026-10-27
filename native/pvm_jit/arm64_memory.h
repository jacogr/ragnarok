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
/* Each exclusive arena owns fixed executable and writable mappings; published bytes never change. */
typedef struct { void *memory; void *writable; uint32_t used; uint32_t capacity; } pvm_arm64_arena;
static void *pvm_arm64_arena_create(void) {
#if defined(__APPLE__) && defined(__aarch64__)
    const uint32_t capacity = 1024 * 1024;
    pvm_arm64_arena *owner = calloc(1, sizeof(*owner));
    if (!owner) return NULL;
    owner->memory = mmap(NULL, capacity, PROT_READ | PROT_WRITE | PROT_EXEC,
                        MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (owner->memory == MAP_FAILED) { free(owner); return NULL; }
    owner->capacity = capacity;
    owner->writable = owner->memory;
    pthread_jit_write_protect_np(1);
    return owner;
#elif defined(__linux__) && defined(__aarch64__)
    const uint32_t capacity = 1024 * 1024;
    pvm_arm64_arena *owner = calloc(1, sizeof(*owner));
    if (!owner) return NULL;
    int descriptor = memfd_create("ragnarok-pvm-code", MFD_CLOEXEC);
    if (descriptor < 0) { free(owner); return NULL; }
    if (ftruncate(descriptor, capacity) != 0) { close(descriptor); free(owner); return NULL; }
    /* Distinct shared aliases keep every mapping either writable or executable, never both. */
    owner->writable = mmap(NULL, capacity, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
    if (owner->writable == MAP_FAILED) { close(descriptor); free(owner); return NULL; }
    owner->memory = mmap(NULL, capacity, PROT_READ | PROT_EXEC, MAP_SHARED, descriptor, 0);
    close(descriptor);
    if (owner->memory == MAP_FAILED) {
        munmap(owner->writable, capacity);
        free(owner);
        return NULL;
    }
    owner->capacity = capacity;
    return owner;
#else
    /* Unsupported platforms refuse before allocation or execution. */
    return NULL;
#endif
}
static void pvm_arm64_arena_destroy(void *handle) {
    if (!handle) return;
#if PVM_ARM64_JIT_HOST
    pvm_arm64_arena *owner = handle;
    if (owner->writable != owner->memory) munmap(owner->writable, owner->capacity);
    munmap(owner->memory, owner->capacity);
#endif
    free(handle);
}
static int32_t pvm_arm64_arena_publish(void *handle, const uint32_t *words, uint32_t count) {
#if PVM_ARM64_JIT_HOST
    pvm_arm64_arena *owner = handle;
    if (!owner || !words || count == 0 || count > 1024) return -1;
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
#if PVM_ARM64_JIT_HOST
    pvm_arm64_arena *owner = handle;
    if (!owner || !registers || offset >= owner->used || (offset & 3)) return UINT32_MAX;
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
    if (!owner || !registers || !state || offset >= owner->used || (offset & 3)) return UINT32_MAX;
    uint32_t (*entry)(void *, void *) =
        (uint32_t (*)(void *, void *))((unsigned char *)owner->memory + offset);
    return entry(registers, state);
#else
    (void)handle; (void)offset; (void)registers; (void)state;
    return UINT32_MAX;
#endif
}

/* The fixed executable base is a non-owning view; only the matching arena handle owns its lifetime. */
static void *pvm_arm64_arena_base(void *handle) {
#if PVM_ARM64_JIT_HOST
    const pvm_arm64_arena *owner = handle;
    return owner ? owner->memory : NULL;
#else
    /* Unsupported hosts never expose an executable view. */
    (void)handle;
    return NULL;
#endif
}
/* Seal only owned aligned publication starts supplied by Nim, before storing their relative coordinates. */
static int pvm_arm64_arena_seal(void *handle, void *base, uint32_t offset) {
#if PVM_ARM64_JIT_HOST
    const pvm_arm64_arena *owner = handle;
    return owner && base && base == owner->memory && offset < owner->used && !(offset & 3);
#else
    /* No unsupported target can establish a callable entry. */
    (void)handle; (void)base; (void)offset;
    return 0;
#endif
}
/* Preconditions: the parent arena remains alive and this base/offset pair was sealed after publication.
 * The arena is fixed and append-only, so range/alignment proofs survive every subsequent publication.
 * Fresh invocation pointers are checked here and never retained by these OS-service calls. */
static int pvm_arm64_entry_call(void *base, uint32_t offset, void *registers) {
#if PVM_ARM64_JIT_HOST
    if (!base || !registers) return 0;
    void (*function)(void *) = (void (*)(void *))((unsigned char *)base + offset);
    function(registers);
    return 1;
#else
    /* Unsupported hosts never invoke supplied addresses. */
    (void)base; (void)offset; (void)registers;
    return 0;
#endif
}
/* A sealed conditional body returns a scalar stream coordinate, never its borrowed code base. */
static uint32_t pvm_arm64_entry_next(void *base, uint32_t offset, void *registers) {
#if PVM_ARM64_JIT_HOST
    if (!base || !registers) return UINT32_MAX;
    uint32_t (*function)(void *) = (uint32_t (*)(void *))((unsigned char *)base + offset);
    return function(registers);
#else
    /* Unsupported hosts cannot manufacture a successful continuation. */
    (void)base; (void)offset; (void)registers;
    return UINT32_MAX;
#endif
}
/* A connected body additionally borrows one fresh context; the same parent-owned entry proof applies. */
static uint32_t pvm_arm64_entry_region(void *base, uint32_t offset, void *registers, void *state) {
#if PVM_ARM64_JIT_HOST
    if (!base || !registers || !state) return UINT32_MAX;
    uint32_t (*function)(void *, void *) =
        (uint32_t (*)(void *, void *))((unsigned char *)base + offset);
    return function(registers, state);
#else
    /* Neither borrowed pointer is dereferenced on an unsupported host. */
    (void)base; (void)offset; (void)registers; (void)state;
    return UINT32_MAX;
#endif
}

#endif
