/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Bounded Linux x86-64 executable storage. Guest semantics and source admission remain in Nim.
 */
#ifndef RAGNAROK_X86_JIT_MEMORY_H
#define RAGNAROK_X86_JIT_MEMORY_H
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include "arena_retirement.h"
#include <string.h>
#include <time.h>
#if defined(__linux__) && defined(__x86_64__)
#include <sys/mman.h>
#include <unistd.h>
#include <linux/memfd.h>
extern int memfd_create(const char *name, unsigned int flags);
#define PVM_X86_JIT_HOST 1
#else
#define PVM_X86_JIT_HOST 0
#endif
/* Each arena embeds its cleanup record before acquiring either OS alias. */
typedef struct {
    pvm_arena_retirement_owner retirement;
    void *executable; void *writable; uint32_t used; unsigned mapped;
} pvm_x86_arena;
_Static_assert(offsetof(pvm_x86_arena, retirement) == 0, "arena cleanup prefix");
#ifdef PVM_NATIVE_RETIREMENT_WITNESS
#include <errno.h>
static void pvm_x86_arena_refuse_unmaps(void *handle, unsigned count) {
    /* The generic owner remains live through a refused physical release. */
    if (handle) pvm_arena_refuse_unmaps(&((pvm_x86_arena *)handle)->retirement, count);
}
#endif
#if PVM_X86_JIT_HOST
static int pvm_x86_arena_unmap(pvm_x86_arena *owner, void *address, size_t bytes) {
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
static int pvm_x86_arena_release_locked(pvm_arena_retirement_owner *record) {
    /* Static prefix layout binds this callback to the exact original arena and alias flags. */
    pvm_x86_arena *owner = (pvm_x86_arena *)record;
#if PVM_X86_JIT_HOST
    if ((owner->mapped & 1) && (!(owner->mapped & 2) || owner->writable != owner->executable)) {
        if (pvm_x86_arena_unmap(owner, owner->writable, (1024 * 1024)) != 0) return 0;
        owner->mapped &= ~1u;
        owner->writable = NULL;
    }
    if (owner->mapped & 2) {
        int shared = (owner->mapped & 1) && owner->writable == owner->executable;
        if (pvm_x86_arena_unmap(owner, owner->executable, (1024 * 1024)) != 0) return 0;
        owner->mapped &= ~2u;
        owner->executable = NULL;
        if (shared) { owner->mapped &= ~1u; owner->writable = NULL; }
    }
#endif
    free(owner);
    return 1;
}
static inline int pvm_x86_arena_try_destroy(void *handle) {
    /* The caller retains the handle on failure; publication and invocation stay disarmed. */
    return pvm_arena_try_release((pvm_arena_retirement_owner *)handle);
}
static void pvm_x86_arena_destroy(void *handle) {
    /* Last-drop cannot return an error; its embedded record survives a failed OS release. */
    pvm_arena_drop((pvm_arena_retirement_owner *)handle);
}
static void *pvm_x86_arena_create_owned(pvm_arena_retirement_state *state) {
    /* Return an owned, non-callable cleanup handle if acquisition failed after a mapping survived. */
#if PVM_X86_JIT_HOST
    const uint32_t capacity = 1024 * 1024;
    pvm_arena_lock(state);
    if (!pvm_arena_drain_locked(state)) { pvm_arena_unlock(state); return NULL; }
    pvm_x86_arena *owner = calloc(1, sizeof(*owner));
    if (!owner) { pvm_arena_unlock(state); return NULL; }
    pvm_arena_retirement_init(&owner->retirement, state, pvm_x86_arena_release_locked);
    int descriptor = memfd_create("ragnarok-pvm-x86-code", MFD_CLOEXEC);
    if (descriptor < 0) goto failed;
    if (ftruncate(descriptor, capacity) != 0) { close(descriptor); goto failed; }
    owner->writable = mmap(NULL, capacity, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
    if (owner->writable == MAP_FAILED) { owner->writable = NULL; close(descriptor); goto failed; }
    owner->mapped = 1;
    if (!owner->writable) { close(descriptor); goto failed; }
#ifdef PVM_NATIVE_RETIREMENT_WITNESS
    if (pvm_arena_fail_acquisition_locked(&owner->retirement)) { close(descriptor); goto failed; }
#endif
    owner->executable = mmap(NULL, capacity, PROT_READ | PROT_EXEC, MAP_SHARED, descriptor, 0);
    close(descriptor);
    if (owner->executable == MAP_FAILED) { owner->executable = NULL; goto failed; }
    owner->mapped |= 2;
    if (!owner->executable) goto failed;
    pvm_arena_unlock(state);
    return owner;
failed:
    owner->retirement.retiring = 1;
    if (pvm_x86_arena_release_locked(&owner->retirement)) owner = NULL;
    pvm_arena_unlock(state);
    return owner;
#else
    (void)state;
    return NULL;
#endif
}
static void *pvm_x86_arena_create(void) {
    /* Legacy direct owners receive callable arenas only; failed acquisition still retains cleanup. */
    pvm_x86_arena *owner = pvm_x86_arena_create_owned(pvm_arena_retirement_state_address());
    if (owner && owner->retirement.retiring) { pvm_x86_arena_destroy(owner); return NULL; }
    return owner;
}
/* Profiling has an explicit unavailable sentinel; no guest operation depends on this clock. */
static uint64_t pvm_x86_cpu_ns(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &now) != 0) return 0;
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}
/* Append a complete bounded leaf, preserving prior code; return its aligned offset or a local refusal. */
static int32_t pvm_x86_arena_publish(void *handle, const unsigned char *bytes, uint32_t length) {
#if PVM_X86_JIT_HOST
    pvm_x86_arena *owner = handle;
    if (!owner || owner->retirement.retiring || !bytes || length == 0 || length > 4096 || owner->used > 1024 * 1024) return -1;
    uint32_t offset = (owner->used + 15) & ~UINT32_C(15);
    if (offset > 1024 * 1024 || length > 1024 * 1024 - offset) return -1;
    /* Publication is append-only; native callers receive offsets only after the new bytes exist. */
    memset((unsigned char *)owner->writable + owner->used, 0x90, offset - owner->used);
    memcpy((unsigned char *)owner->writable + offset, bytes, length);
    __builtin___clear_cache((char *)owner->executable + offset, (char *)owner->executable + offset + length);
    owner->used = offset + length;
    return (int32_t)offset;
#else
    (void)handle; (void)bytes; (void)length;
    return -1;
#endif
}
/* Invoke only a cache-validated native entry with fresh borrowed registers; malformed scalar extents refuse. */
static int pvm_x86_arena_call(void *handle, uint32_t offset, void *registers) {
#if PVM_X86_JIT_HOST
    pvm_x86_arena *owner = handle;
    if (!owner || owner->retirement.retiring || !registers || offset >= owner->used || (offset & 15)) return 0;
    /* Only the Nim cache's admitted entry records call this private pointer boundary. */
    void (*entry)(void *) = (void (*)(void *))((unsigned char *)owner->executable + offset);
    entry(registers);
    return 1;
#else
    (void)handle; (void)offset; (void)registers;
    return 0;
#endif
}
/* Return one previously admitted scalar stream offset; no guest or invocation pointer is returned. */
static uint32_t pvm_x86_arena_next(void *handle, uint32_t offset, void *registers) {
#if PVM_X86_JIT_HOST
    pvm_x86_arena *owner = handle;
    if (!owner || owner->retirement.retiring || !registers || offset >= owner->used || (offset & 15)) return UINT32_MAX;
    uint32_t (*entry)(void *) = (uint32_t (*)(void *))((unsigned char *)owner->executable + offset);
    return entry(registers);
#else
    (void)handle; (void)offset; (void)registers;
    return UINT32_MAX;
#endif
}
/* Invoke a sealed connected entry with two invocation-local borrows; no context survives return. */
static uint32_t pvm_x86_arena_region(void *handle, uint32_t offset, void *registers, void *state) {
#if PVM_X86_JIT_HOST
    pvm_x86_arena *owner = handle;
    if (!owner || owner->retirement.retiring || !registers || !state || offset >= owner->used || (offset & 15)) return UINT32_MAX;
    uint32_t (*entry)(void *, void *) = (uint32_t (*)(void *, void *))((unsigned char *)owner->executable + offset);
    return entry(registers, state);
#else
    (void)handle; (void)offset; (void)registers; (void)state;
    return UINT32_MAX;
#endif
}

/* One call's clipped private bytes; all addresses are unsigned guest addresses, and end is exclusive. */
typedef struct {
    const uint8_t *read_ptr;
    uint64_t read_first;
    uint64_t read_end;
    uint8_t *write_ptr;
    uint64_t write_first;
    uint64_t write_end;
    uint32_t dirty_words;
    uint32_t reserved;
} pvm_x86_cycle_memory;

/* Each visit counts a completed original block; a word group completes four dirty blocks. */
typedef struct {
    uint64_t gas;
    uint64_t attempts;
    uint64_t visits[3];
    uint64_t word_groups;
    uint32_t last_completed;
    uint32_t exit_kind;
    uint64_t reserved;
} pvm_x86_cycle_state;

_Static_assert(sizeof(pvm_x86_cycle_memory) == 56 &&
    offsetof(pvm_x86_cycle_memory, dirty_words) == 48, "x86 cycle memory ABI");
_Static_assert(sizeof(pvm_x86_cycle_state) == 64 &&
    offsetof(pvm_x86_cycle_state, last_completed) == 48 &&
    offsetof(pvm_x86_cycle_state, exit_kind) == 52, "x86 cycle state ABI");

/* A wider private call keeps the proven child ABI at offset zero and adds only fresh read extents. */
typedef struct {
    const uint8_t *data;
    uint64_t first;
    uint64_t ending;
} pvm_x86_wide_read_region;
typedef struct {
    pvm_x86_cycle_memory cycle;
    pvm_x86_wide_read_region regions[3];
} pvm_x86_wide_memory;
typedef struct {
    pvm_x86_cycle_state cycle;
    uint64_t outer_visits[4];
    uint64_t child_calls;
} pvm_x86_wide_state;
_Static_assert(sizeof(pvm_x86_wide_memory) == 128 &&
    offsetof(pvm_x86_wide_memory, regions) == 56 &&
    sizeof(pvm_x86_wide_state) == 104 &&
    offsetof(pvm_x86_wide_state, outer_visits) == 64 &&
    offsetof(pvm_x86_wide_state, child_calls) == 96, "x86 wide cycle ABI");

/* The high word distinguishes an untouched pre-call refusal from any return after native execution. */
static uint64_t pvm_x86_arena_cycle(void *handle, uint32_t offset, uint64_t *registers,
        const pvm_x86_cycle_memory *memory, const uint64_t *dirty_bitmap,
        pvm_x86_cycle_state *state) {
#if PVM_X86_JIT_HOST
    pvm_x86_arena *owner = handle;
    if (!owner || owner->retirement.retiring || !registers || !memory || !state || !memory->write_ptr ||
            (memory->dirty_words != 0 && !dirty_bitmap) ||
            (memory->read_ptr == NULL && memory->read_first != memory->read_end) ||
            offset >= owner->used || (offset & 15)) return 0;
    typedef uint32_t (*entry_type)(uint64_t *, const pvm_x86_cycle_memory *,
        const uint64_t *, pvm_x86_cycle_state *);
    entry_type entry = (entry_type)((uint8_t *)owner->executable + offset);
    return (UINT64_C(1) << 32) | (uint64_t)entry(registers, memory, dirty_bitmap, state);
#else
    (void)handle; (void)offset; (void)registers; (void)memory;
    (void)dirty_bitmap; (void)state;
    return 0;
#endif
}

/* The wider entry borrows four complete typed inputs; a zero high word proves pre-call refusal. */
static uint64_t pvm_x86_arena_wide(void *handle, uint32_t offset, uint64_t *registers,
        const pvm_x86_wide_memory *memory, const uint64_t *dirty_bitmap,
        pvm_x86_wide_state *state) {
#if PVM_X86_JIT_HOST
    pvm_x86_arena *owner = handle;
    if (!owner || owner->retirement.retiring || !registers || !memory || !state || !memory->cycle.write_ptr ||
            (memory->cycle.dirty_words != 0 && !dirty_bitmap) ||
            (memory->cycle.read_ptr == NULL &&
                memory->cycle.read_first != memory->cycle.read_end) ||
            offset >= owner->used || (offset & 15)) return 0;
    typedef uint32_t (*entry_type)(uint64_t *, const pvm_x86_wide_memory *,
        const uint64_t *, pvm_x86_wide_state *);
    entry_type entry = (entry_type)((uint8_t *)owner->executable + offset);
    return (UINT64_C(1) << 32) | (uint64_t)entry(registers, memory, dirty_bitmap, state);
#else
    (void)handle; (void)offset; (void)registers; (void)memory;
    (void)dirty_bitmap; (void)state;
    return 0;
#endif
}
#endif
