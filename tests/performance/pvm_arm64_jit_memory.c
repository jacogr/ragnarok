/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Local executable-storage boundary/retirement checks; no PVM semantics live here.
 */
#include <assert.h>
#include <stdio.h>
#include "arm64_memory.h"
int main(void) {
    uint32_t words[1024];
    uint64_t registers[13] = {0};
    for (unsigned i = 0; i < 1024; ++i) words[i] = UINT32_C(0xd65f03c0);
    assert(pvm_arm64_jit_cpu_ns() > 0);
    assert(pvm_arm64_arena_publish(NULL, words, 1) == -1);
    assert(pvm_arm64_arena_call(NULL, 0, registers) == 0);
    assert(pvm_arm64_arena_next(NULL, 0, registers) == UINT32_MAX);
    pvm_arm64_arena_destroy(NULL);
    for (unsigned cycle = 0; cycle < 1000; ++cycle) {
        /* Each mapping is retired before the next is created; successful calls borrow only registers. */
        void *arena = pvm_arm64_arena_create();
        assert(arena != NULL);
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
    pvm_arm64_arena_destroy(continuation);
    /* Exact final capacity is admitted; subsequent publication refuses without extending the mapping. */
    void *arena = pvm_arm64_arena_create();
    assert(arena != NULL);
    for (unsigned fragment = 0; fragment < 256; ++fragment) {
        assert(pvm_arm64_arena_publish(arena, words, 1024) == (int32_t)(fragment * 4096));
    }
    assert(pvm_arm64_arena_publish(arena, words, 1) == -1);
    pvm_arm64_arena_destroy(arena);
    puts("ARM_MEMORY_OK,1000,capacity,publication,retirement");
    return 0;
}
