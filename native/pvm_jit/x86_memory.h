/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Bounded Linux x86-64 executable storage. Guest semantics and source admission remain in Nim.
 */
#ifndef RAGNAROK_X86_JIT_MEMORY_H
#define RAGNAROK_X86_JIT_MEMORY_H
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
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
/* Each exclusive owner retains one MiB, with separate writable and executable aliases. */
typedef struct { void *executable; void *writable; uint32_t used; } pvm_x86_arena;
/* Return process CPU time for cold publication accounting; a missing OS clock is an internal failure. */
static uint64_t pvm_x86_cpu_ns(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &now) != 0) abort();
    return (uint64_t)now.tv_sec * UINT64_C(1000000000) + (uint64_t)now.tv_nsec;
}
/* Allocate an exclusive bounded pair of aliases; unsupported hosts or OS refusal return no capability. */
static void *pvm_x86_arena_create(void) {
#if PVM_X86_JIT_HOST
    const uint32_t capacity = 1024 * 1024;
    pvm_x86_arena *owner = calloc(1, sizeof(*owner));
    if (!owner) return NULL;
    int fd = memfd_create("ragnarok-pvm-x86-code", MFD_CLOEXEC);
    if (fd < 0) { free(owner); return NULL; }
    if (ftruncate(fd, capacity) != 0) { close(fd); free(owner); return NULL; }
    owner->writable = mmap(NULL, capacity, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (owner->writable == MAP_FAILED) { close(fd); free(owner); return NULL; }
    owner->executable = mmap(NULL, capacity, PROT_READ | PROT_EXEC, MAP_SHARED, fd, 0);
    close(fd);
    if (owner->executable == MAP_FAILED) {
        munmap(owner->writable, capacity); free(owner); return NULL;
    }
    return owner;
#else
    return NULL;
#endif
}
/* Retire only this owner's mappings; default and moved-from handles release nothing. */
static void pvm_x86_arena_destroy(void *handle) {
    if (!handle) return;
#if PVM_X86_JIT_HOST
    pvm_x86_arena *owner = handle;
    munmap(owner->writable, 1024 * 1024);
    munmap(owner->executable, 1024 * 1024);
#endif
    free(handle);
}
/* Append a complete bounded leaf, preserving prior code; return its aligned offset or a local refusal. */
static int32_t pvm_x86_arena_publish(void *handle, const unsigned char *bytes, uint32_t length) {
#if PVM_X86_JIT_HOST
    pvm_x86_arena *owner = handle;
    if (!owner || !bytes || length == 0 || length > 4096 || owner->used > 1024 * 1024) return -1;
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
    if (!owner || !registers || offset >= owner->used || (offset & 15)) return 0;
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
    if (!owner || !registers || offset >= owner->used || (offset & 15)) return UINT32_MAX;
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
    if (!owner || !registers || !state || offset >= owner->used || (offset & 15)) return UINT32_MAX;
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
    if (!owner || !registers || !memory || !state || !memory->write_ptr ||
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
    if (!owner || !registers || !memory || !state || !memory->cycle.write_ptr ||
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
