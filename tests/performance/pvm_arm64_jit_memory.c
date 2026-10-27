/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Local executable-storage boundary/retirement checks; no PVM semantics live here.
 */
#include <assert.h>
#include <stdio.h>
#if defined(__linux__) && defined(__aarch64__)
#include <sys/mman.h>
#include <dirent.h>
#include <errno.h>
/* Fail the selected real mapping attempt to exercise descriptor/alias cleanup on both paths. */
static unsigned fail_mapping = 0;
static void *test_mmap(void *address, size_t length, int protection, int flags, int descriptor,
                       off_t offset) {
    if (fail_mapping && --fail_mapping == 0) { errno = ENOMEM; return MAP_FAILED; }
    return mmap(address, length, protection, flags, descriptor, offset);
}
#define mmap test_mmap
#endif
#include "arm64_memory.h"
#if defined(__linux__) && defined(__aarch64__)
#undef mmap
/* Counting our own open descriptors proves failed aliases and successful arenas do not leak memfds. */
static unsigned descriptor_count(void) {
    DIR *directory = opendir("/proc/self/fd");
    assert(directory != NULL);
    unsigned count = 0;
    struct dirent *entry = NULL;
    while ((entry = readdir(directory)) != NULL) {
        if (strcmp(entry->d_name, ".") && strcmp(entry->d_name, "..")) ++count;
    }
    assert(closedir(directory) == 0);
    return count;
}
/* Every live code alias must have precisely its intended write/execute permissions. */
static void mapping_permissions(void *address, int writable, int executable) {
    FILE *maps = fopen("/proc/self/maps", "r");
    assert(maps != NULL);
    char line[512];
    int found = 0;
    while (fgets(line, sizeof(line), maps)) {
        unsigned long first = 0, last = 0;
        char flags[5] = {0};
        if (sscanf(line, "%lx-%lx %4s", &first, &last, flags) != 3) continue;
        if ((uintptr_t)address >= first && (uintptr_t)address < last) {
            assert(flags[0] == 'r');
            assert((flags[1] == 'w') == writable);
            assert((flags[2] == 'x') == executable);
            found = 1;
            break;
        }
    }
    assert(fclose(maps) == 0 && found);
}
#endif
int main(void) {
    uint32_t words[1024];
    uint64_t registers[13] = {0};
    for (unsigned i = 0; i < 1024; ++i) words[i] = UINT32_C(0xd65f03c0);
    assert(pvm_arm64_jit_cpu_ns() > 0);
#if defined(__linux__) && defined(__aarch64__)
    unsigned descriptors = descriptor_count();
    for (unsigned position = 1; position <= 2; ++position) {
        fail_mapping = position;
        assert(pvm_arm64_arena_create() == NULL);
        assert(fail_mapping == 0 && descriptor_count() == descriptors);
    }
#endif
    assert(pvm_arm64_arena_publish(NULL, words, 1) == -1);
    assert(pvm_arm64_arena_call(NULL, 0, registers) == 0);
    assert(pvm_arm64_arena_next(NULL, 0, registers) == UINT32_MAX);
    pvm_arm64_arena_destroy(NULL);
    for (unsigned cycle = 0; cycle < 1000; ++cycle) {
        /* Each mapping is retired before the next is created; successful calls borrow only registers. */
        void *arena = pvm_arm64_arena_create();
        assert(arena != NULL);
#if defined(__linux__) && defined(__aarch64__)
        mapping_permissions(((pvm_arm64_arena *)arena)->memory, 0, 1);
        mapping_permissions(((pvm_arm64_arena *)arena)->writable, 1, 0);
#endif
        assert(pvm_arm64_arena_publish(arena, NULL, 1) == -1);
        assert(pvm_arm64_arena_publish(arena, words, 0) == -1);
        assert(pvm_arm64_arena_publish(arena, words, 1025) == -1);
        int32_t offset = pvm_arm64_arena_publish(arena, words, 1);
        assert(offset == 0);
        assert(pvm_arm64_arena_call(arena, 0, registers) == 1);
        assert(pvm_arm64_arena_call(arena, 1, registers) == 0);
        assert(pvm_arm64_arena_call(arena, 4, registers) == 0);
        assert(pvm_arm64_arena_call(arena, 0, NULL) == 0);
        pvm_arm64_arena_destroy(arena);
    }
    /* Returning leaves preserve their scalar ABI; invalid offsets refuse before entering generated code. */
    void *continuation = pvm_arm64_arena_create();
    assert(continuation != NULL);
    uint32_t returning[] = { UINT32_C(0x528000e0), UINT32_C(0xd65f03c0) }; /* MOV W0,#7; RET */
    assert(pvm_arm64_arena_publish(continuation, returning, 2) == 0);
    assert(pvm_arm64_arena_next(continuation, 0, registers) == 7);
    assert(pvm_arm64_arena_next(continuation, 1, registers) == UINT32_MAX);
    assert(pvm_arm64_arena_next(continuation, 8, registers) == UINT32_MAX);
    assert(pvm_arm64_arena_next(continuation, 0, NULL) == UINT32_MAX);
    /* Connected-call ABI borrows a separate context and refuses incomplete pointers before native entry. */
    uint64_t context[5] = {11, 22, 33, 44, 55};
    assert(pvm_arm64_arena_region(NULL, 0, registers, context) == UINT32_MAX);
    assert(pvm_arm64_arena_region(continuation, 0, registers, context) == 7);
    assert(pvm_arm64_arena_region(continuation, 1, registers, context) == UINT32_MAX);
    assert(pvm_arm64_arena_region(continuation, 8, registers, context) == UINT32_MAX);
    assert(pvm_arm64_arena_region(continuation, 0, NULL, context) == UINT32_MAX);
    assert(pvm_arm64_arena_region(continuation, 0, registers, NULL) == UINT32_MAX);
    for (unsigned slot = 0; slot < 5; ++slot) assert(context[slot] == 11 * (slot + 1));
    /* Appending code preserves the prior publication and makes the new instruction bytes executable. */
    uint32_t appended[] = { UINT32_C(0x52800120), UINT32_C(0xd65f03c0) }; /* MOV W0,#9; RET */
    assert(pvm_arm64_arena_publish(continuation, appended, 2) == 8);
    assert(pvm_arm64_arena_next(continuation, 0, registers) == 7);
    assert(pvm_arm64_arena_next(continuation, 8, registers) == 9);
    pvm_arm64_arena_destroy(continuation);
    /* SIMD scalar ADD is integer arithmetic: exact carries beyond 2^53 and modular 64-bit wrap must survive execution. */
    void *integer_arena = pvm_arm64_arena_create();
    assert(integer_arena != NULL);
    uint32_t integer_words[] = {
        UINT32_C(0xaa0103f1), /* MOV X17,X1: borrow the context without touching register-file bytes. */
        UINT32_C(0xfd400a30), /* LDR D16,[X17,#16]. */
        UINT32_C(0xfd400e33), /* LDR D19,[X17,#24]. */
        UINT32_C(0x5ef38610), /* ADD D16,D16,D19: integer, not FADD. */
        UINT32_C(0xfd001230), /* STR D16,[X17,#32]. */
        UINT32_C(0x528009a0), UINT32_C(0xd65f03c0) /* MOV W0,#77; RET. */
    };
    assert(pvm_arm64_arena_publish(integer_arena, integer_words, 7) == 0);
    const uint64_t integer_values[] = {0, 1, UINT64_C(0x1fffffffffffff),
        UINT64_C(0x20000000000000), UINT64_C(0x20000000000001),
        UINT64_C(0x8000000000000000), UINT64_MAX - 1, UINT64_MAX};
    for (unsigned slot = 0; slot < 13; ++slot) registers[slot] = UINT64_C(0xfedcba9876543210) + slot;
    for (unsigned left = 0; left < 8; ++left) {
        for (unsigned right = 0; right < 8; ++right) {
            /* Every context field and borrowed register byte outside the one declared result remains unchanged. */
            uint64_t integer_context[5] = {11, 22, integer_values[left], integer_values[right], 0};
            assert(pvm_arm64_arena_region(integer_arena, 0, registers, integer_context) == 77);
            assert(integer_context[0] == 11 && integer_context[1] == 22);
            assert(integer_context[2] == integer_values[left] && integer_context[3] == integer_values[right]);
            assert(integer_context[4] == integer_values[left] + integer_values[right]);
            for (unsigned slot = 0; slot < 13; ++slot) {
                assert(registers[slot] == UINT64_C(0xfedcba9876543210) + slot);
            }
        }
    }
    pvm_arm64_arena_destroy(integer_arena);
    /* Exact final capacity is admitted; subsequent publication refuses without extending the mapping. */
    void *arena = pvm_arm64_arena_create();
    assert(arena != NULL);
    for (unsigned fragment = 0; fragment < 256; ++fragment) {
        assert(pvm_arm64_arena_publish(arena, words, 1024) == (int32_t)(fragment * 4096));
    }
    assert(pvm_arm64_arena_publish(arena, words, 1) == -1);
    pvm_arm64_arena_destroy(arena);
#if defined(__linux__) && defined(__aarch64__)
    assert(descriptor_count() == descriptors);
#endif
    puts("ARM_MEMORY_OK,1000,capacity,publication,retirement,integer64");
    return 0;
}
