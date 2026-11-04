/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Exercise executable publication, immutable old entries, bounded capacity and repeated owner retirement.
 */
#include <assert.h>
#include <stdio.h>
#include "x86_memory.h"
int main(void) {
    for (int repeat = 0; repeat < 1000; ++repeat) {
        void *owner = pvm_x86_arena_create();
#if PVM_X86_JIT_HOST
        assert(owner);
        unsigned char bytes[] = {0x48,0xb8,0x88,0x77,0x66,0x55,0x44,0x33,0x22,0x11,
                                 0x48,0x89,0x07,0xc3};
        uint64_t registers[13] = {0};
        assert(pvm_x86_arena_publish(owner, bytes, 0) == -1);
        assert(pvm_x86_arena_publish(owner, NULL, sizeof(bytes)) == -1);
        assert(pvm_x86_arena_publish(owner, bytes, 4097) == -1);
        int32_t first = pvm_x86_arena_publish(owner, bytes, sizeof(bytes));
        assert(first == 0);
        assert(pvm_x86_arena_call(owner, first + 1, registers) == 0);
        assert(pvm_x86_arena_call(owner, 1024 * 1024, registers) == 0);
        assert(pvm_x86_arena_call(owner, first, registers) == 1);
        assert(registers[0] == UINT64_C(0x1122334455667788));
        bytes[2] = 0x99;
        int32_t second = pvm_x86_arena_publish(owner, bytes, sizeof(bytes));
        assert(second == 16);
        assert(pvm_x86_arena_call(owner, second, registers) == 1);
        assert(registers[0] == UINT64_C(0x1122334455667799));
        assert(pvm_x86_arena_call(owner, first, registers) == 1);
        assert(registers[0] == UINT64_C(0x1122334455667788));
        /* Conditional leaves return a checked scalar coordinate, with immutable earlier entries still callable. */
        const unsigned char next_bytes[] = {0xb8, 42, 0, 0, 0, 0xc3};
        int32_t next = pvm_x86_arena_publish(owner, next_bytes, sizeof(next_bytes));
        assert(next == 32);
        assert(pvm_x86_arena_next(owner, next, registers) == 42);
        assert(pvm_x86_arena_next(owner, next + 1, registers) == UINT32_MAX);
        assert(pvm_x86_arena_next(NULL, next, registers) == UINT32_MAX);
        /* Connected entries borrow RDI registers and RSI context independently, committing neither on refusal. */
        const unsigned char region_bytes[] = {0x48,0xc7,0x06,7,0,0,0,
                                             0x48,0xc7,0x07,9,0,0,0,0xb8,42,0,0,0,0xc3};
        uint64_t state[5] = {0};
        int32_t region = pvm_x86_arena_publish(owner, region_bytes, sizeof(region_bytes));
        assert(region >= 0);
        assert(pvm_x86_arena_region(owner, region, registers, state) == 42);
        assert(registers[0] == 9 && state[0] == 7);
        assert(pvm_x86_arena_region(NULL, region, registers, state) == UINT32_MAX);
        assert(pvm_x86_arena_region(owner, region, NULL, state) == UINT32_MAX);
        assert(pvm_x86_arena_region(owner, region, registers, NULL) == UINT32_MAX);
        assert(pvm_x86_arena_region(owner, region + 1, registers, state) == UINT32_MAX);
        assert(pvm_x86_arena_region(owner, 1024 * 1024, registers, state) == UINT32_MAX);
        assert(registers[0] == 9 && state[0] == 7);
        /* Typed cycle entries keep a distinct successful receipt and refuse invalid borrows before execution. */
        unsigned char cell = 0;
        uint64_t dirty = 0;
        pvm_x86_cycle_memory cycle_memory = { .write_ptr = &cell, .dirty_words = 1 };
        pvm_x86_cycle_state cycle_state = { .gas = 5, .attempts = 7 };
        const uint64_t receipt = (UINT64_C(1) << 32) | UINT64_C(42);
        assert(pvm_x86_arena_cycle(owner, next, registers, &cycle_memory, &dirty,
            &cycle_state) == receipt);
        assert(pvm_x86_arena_cycle(NULL, next, registers, &cycle_memory, &dirty,
            &cycle_state) == 0);
        assert(pvm_x86_arena_cycle(owner, next + 1, registers, &cycle_memory, &dirty,
            &cycle_state) == 0);
        assert(pvm_x86_arena_cycle(owner, next, NULL, &cycle_memory, &dirty, &cycle_state) == 0);
        assert(pvm_x86_arena_cycle(owner, next, registers, NULL, &dirty, &cycle_state) == 0);
        assert(pvm_x86_arena_cycle(owner, next, registers, &cycle_memory, NULL, &cycle_state) == 0);
        assert(pvm_x86_arena_cycle(owner, next, registers, &cycle_memory, &dirty, NULL) == 0);
        cycle_memory.write_ptr = NULL;
        assert(pvm_x86_arena_cycle(owner, next, registers, &cycle_memory, &dirty,
            &cycle_state) == 0);
        cycle_memory.write_ptr = &cell;
        cycle_memory.read_end = 1;
        assert(pvm_x86_arena_cycle(owner, next, registers, &cycle_memory, &dirty,
            &cycle_state) == 0);
        cycle_memory.read_end = 0;
        /* The wider ABI borrows the same prefix without changing the successful high-word contract. */
        pvm_x86_wide_memory wide_memory = { .cycle = cycle_memory };
        pvm_x86_wide_state wide_state = { .cycle = { .gas = 5, .attempts = 7 } };
        assert(pvm_x86_arena_wide(owner, next, registers, &wide_memory, &dirty,
            &wide_state) == receipt);
        assert(pvm_x86_arena_wide(NULL, next, registers, &wide_memory, &dirty, &wide_state) == 0);
        assert(pvm_x86_arena_wide(owner, next + 1, registers, &wide_memory, &dirty,
            &wide_state) == 0);
        assert(pvm_x86_arena_wide(owner, next, NULL, &wide_memory, &dirty, &wide_state) == 0);
        assert(pvm_x86_arena_wide(owner, next, registers, NULL, &dirty, &wide_state) == 0);
        assert(pvm_x86_arena_wide(owner, next, registers, &wide_memory, NULL, &wide_state) == 0);
        assert(pvm_x86_arena_wide(owner, next, registers, &wide_memory, &dirty, NULL) == 0);
        wide_memory.cycle.write_ptr = NULL;
        assert(pvm_x86_arena_wide(owner, next, registers, &wide_memory, &dirty, &wide_state) == 0);
        wide_memory.cycle.write_ptr = &cell;
        wide_memory.cycle.read_end = 1;
        assert(pvm_x86_arena_wide(owner, next, registers, &wide_memory, &dirty, &wide_state) == 0);
        assert(registers[0] == 9 && state[0] == 7 && cell == 0 && dirty == 0);
        assert(cycle_state.gas == 5 && cycle_state.attempts == 7);
        assert(wide_state.cycle.gas == 5 && wide_state.cycle.attempts == 7);
        if (repeat == 0) {
            /* Fill the physical arena without executing padding; refusal must preserve the original code. */
            unsigned char fill[4096];
            memset(fill, 0x90, sizeof(fill));
            while (pvm_x86_arena_publish(owner, fill, sizeof(fill)) >= 0) {}
            assert(pvm_x86_arena_publish(owner, fill, sizeof(fill)) == -1);
            assert(pvm_x86_arena_call(owner, first, registers) == 1);
            assert(registers[0] == UINT64_C(0x1122334455667788));
        }
#else
        assert(!owner);
#endif
        pvm_x86_arena_destroy(owner);
        pvm_x86_arena_destroy(NULL);
    }
    assert(pvm_x86_cpu_ns() > 0);
    puts("X86_EXECUTABLE_MEMORY_OK,1000");
    return 0;
}
