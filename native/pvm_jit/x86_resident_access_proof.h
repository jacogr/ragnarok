/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Private literal ISA probe, excluded unless the resident-access proof is selected. */
#ifndef PVM_X86_RESIDENT_ACCESS_PROOF_H
#define PVM_X86_RESIDENT_ACCESS_PROOF_H
#include "x86_memory.h"
#include <stdio.h>

/* Six live hardware sentinels surround the actual four-borrow SysV call. The invocation tag
 * originates here, outside generated state. This helper owns no arena or guest memory. */
static __attribute__((noinline)) uint64_t pvm_x86_resident_access_proof(void *handle,
        uint32_t offset, uint64_t *registers, int check_context) {
#if PVM_X86_JIT_HOST
    pvm_x86_arena *owner = handle;
    if (!owner || !registers || offset >= owner->used || (offset & 15)) return 0;
    uint64_t memory = 0, dirty = 0, context[5] = {0};
    register uint64_t saved_bx __asm__("rbx") = UINT64_C(0x0123456789abcdef);
    register uint64_t saved_bp __asm__("rbp") = UINT64_C(0x123456789abcdef0);
    register uint64_t saved12 __asm__("r12") = UINT64_C(0x23456789abcdef01);
    register uint64_t saved13 __asm__("r13") = UINT64_C(0x3456789abcdef012);
    register uint64_t saved14 __asm__("r14") = UINT64_C(0x456789abcdef0123);
    register uint64_t saved15 __asm__("r15") = UINT64_C(0x56789abcdef01234);
    __asm__ volatile("" : "+r"(saved_bx), "+r"(saved_bp), "+r"(saved12),
        "+r"(saved13), "+r"(saved14), "+r"(saved15));
    uint32_t (*entry)(void *, void *, void *, void *) =
        (uint32_t (*)(void *, void *, void *, void *))((unsigned char *)owner->executable + offset);
    uint32_t next = entry(registers, &memory, &dirty, context);
    __asm__ volatile("" : "+r"(saved_bx), "+r"(saved_bp), "+r"(saved12),
        "+r"(saved13), "+r"(saved14), "+r"(saved15));
    if (saved_bx != UINT64_C(0x0123456789abcdef) || saved_bp != UINT64_C(0x123456789abcdef0) ||
            saved12 != UINT64_C(0x23456789abcdef01) || saved13 != UINT64_C(0x3456789abcdef012) ||
            saved14 != UINT64_C(0x456789abcdef0123) || saved15 != UINT64_C(0x56789abcdef01234)) {
        fputs("X86_RESIDENT_ABI_CLOBBER\n", stderr);
        abort();
    }
    if (check_context && (context[0] != (uintptr_t)registers ||
            context[1] != (uintptr_t)&memory || context[2] != (uintptr_t)&dirty ||
            context[3] != (uintptr_t)context || context[4] != 0)) {
        fputs("X86_RESIDENT_CONTEXT_MISMATCH\n", stderr);
        abort();
    }
    return (UINT64_C(1) << 32) | next;
#else
    (void)handle; (void)offset; (void)registers; (void)check_context;
    return 0;
#endif
}
/* Copy only bounded, actually published RX bytes for this literal backend proof. */
static int pvm_x86_resident_copy_proof(void *handle, uint32_t offset,
        unsigned char *output, uint32_t length) {
#if PVM_X86_JIT_HOST
    pvm_x86_arena *owner = handle;
    if (!owner || !output || !length || length > 4096 || offset >= owner->used ||
            length > owner->used - offset || (offset & 15)) return 0;
    memcpy(output, (const unsigned char *)owner->executable + offset, length);
    return 1;
#else
    (void)handle; (void)offset; (void)output; (void)length;
    return 0;
#endif
}
#endif
