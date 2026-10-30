/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Private whole-program ARM64 experiment: owned immutable executable image and a narrow call ABI.
 * Guest semantics and checked guest memory remain in Nim; no interpreter or fragment arena is used.
 */
#ifndef RAGNAROK_PVM_WHOLE_IMAGE_H
#define RAGNAROK_PVM_WHOLE_IMAGE_H
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/mman.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <pthread.h>
#include <libkern/OSCacheControl.h>
#endif
#if !defined(__aarch64__)
#error "The private whole-program experiment requires ARM64"
#endif
/* Every field offset used by generated code has a fixed explicit 64-bit ABI. */
typedef struct {
    uint64_t registers[13];
    uint64_t status, pc, fault_page, loads, stores, exits;
    void *writer;
} pvm_whole_invocation;
typedef uint64_t (*pvm_whole_load_fn)(void *, uint64_t, uint64_t);
typedef void (*pvm_whole_store_fn)(void *, uint64_t, uint64_t, uint64_t);
typedef struct { void *code; size_t size; } pvm_whole_image;
/* Nimony may inline FFI wrappers across C units: audit counters need one coalesced symbol.
 * These cold counters are serial experiment instrumentation, never guest execution state. */
__attribute__((weak)) uint64_t pvm_whole_created = 0, pvm_whole_destroyed = 0;
static uint64_t pvm_whole_created_count(void) { return pvm_whole_created; }
static uint64_t pvm_whole_destroyed_count(void) { return pvm_whole_destroyed; }
_Static_assert(offsetof(pvm_whole_invocation, status) == 104, "status ABI");
_Static_assert(offsetof(pvm_whole_invocation, writer) == 152, "writer ABI");
_Static_assert(sizeof(pvm_whole_invocation) == 160, "context ABI");
static uint64_t pvm_whole_cpu_ns(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &now) != 0 || now.tv_sec < 0 ||
        now.tv_nsec < 0 || now.tv_nsec >= 1000000000) abort();
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}
static uint64_t pvm_whole_wall_ns(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0 || now.tv_sec < 0 ||
        now.tv_nsec < 0 || now.tv_nsec >= 1000000000) abort();
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}
static uint32_t pvm_whole_context_size(void) { return sizeof(pvm_whole_invocation); }
static int pvm_whole_check_layout(const void *raw) {
    const pvm_whole_invocation *context = raw;
    if (!context || context->status != UINT64_C(0x123456789abcdef0)) return 0;
    for (unsigned i = 0; i < 13; ++i) if (context->registers[i] != i + 1u) return 0;
    return 1;
}
static void *pvm_whole_publish(const uint32_t *words, size_t count) {
    /* This diagnostic owns one full image, bounded independently of production fragment quotas. */
    if (!words || !count || count > (32u * 1024u * 1024u) / 4u) return NULL;
    long page = sysconf(_SC_PAGESIZE);
    if (page <= 0 || (size_t)page > 1024u * 1024u) return NULL;
    size_t bytes = count * 4u;
    size_t size = (bytes + (size_t)page - 1u) / (size_t)page * (size_t)page;
    pvm_whole_image *image = calloc(1, sizeof(*image));
    if (!image) return NULL;
#if defined(__APPLE__)
    image->code = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC,
                       MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
#else
    image->code = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
#endif
    if (image->code == MAP_FAILED) { free(image); return NULL; }
    image->size = size;
#if defined(__APPLE__)
    pthread_jit_write_protect_np(0);
#endif
    memcpy(image->code, words, bytes);
#if defined(__APPLE__)
    sys_icache_invalidate(image->code, bytes);
    pthread_jit_write_protect_np(1);
#else
    __builtin___clear_cache((char *)image->code, (char *)image->code + bytes);
    if (mprotect(image->code, size, PROT_READ | PROT_EXEC) != 0) {
        munmap(image->code, size); free(image); return NULL;
    }
#endif
    ++pvm_whole_created;
    return image;
}
static void pvm_whole_destroy(void *handle) {
    if (!handle) return;
    pvm_whole_image *image = handle;
    if (munmap(image->code, image->size) != 0) abort();
    ++pvm_whole_destroyed;
    free(image);
}
static int pvm_whole_call(void *handle, void *invocation,
                          pvm_whole_load_fn load, pvm_whole_store_fn store) {
    if (!handle || !invocation || !load || !store) return 0;
    pvm_whole_image *image = handle;
    void (*entry)(void *, pvm_whole_load_fn, pvm_whole_store_fn) = image->code;
    entry(invocation, load, store);
    return 1;
}
#endif
