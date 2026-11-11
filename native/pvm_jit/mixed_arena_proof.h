/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Private native witness for immutable mixed entry extents in one arena.
 */
#ifndef RAGNAROK_MIXED_ARENA_PROOF_H
#define RAGNAROK_MIXED_ARENA_PROOF_H

#include <stdint.h>
#include <string.h>
#include <errno.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/mach_vm.h>
#endif

#if defined(__linux__) && defined(__x86_64__)
#include "x86_memory.h"
#elif defined(__aarch64__) && (defined(__APPLE__) || defined(__linux__))
#include "arm64_memory.h"
#endif

/* Capture the mapping address before its heap owner is released. */
static void *pvm_mixed_arena_address(void *handle) {
#if defined(__linux__) && defined(__x86_64__)
    pvm_x86_arena *owner = handle;
    return owner ? owner->executable : NULL;
#elif defined(__aarch64__) && (defined(__APPLE__) || defined(__linux__))
    pvm_arm64_arena *owner = handle;
    return owner ? owner->memory : NULL;
#else
    (void)handle;
    return NULL;
#endif
}

/* The direct fault profiles perform no other allocation between unmapping and this check. */
static int pvm_mixed_arena_unmapped(void *address) {
#if defined(__APPLE__) && defined(__aarch64__)
    if (!address) return 0;
    mach_vm_address_t probe = (mach_vm_address_t)(uintptr_t)address;
    mach_vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t status = mach_vm_region(mach_task_self(), &probe, &size,
        VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object);
    if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
    return status == KERN_INVALID_ADDRESS ||
        (status == KERN_SUCCESS && probe > (mach_vm_address_t)(uintptr_t)address);
#elif defined(__linux__) && (defined(__x86_64__) || defined(__aarch64__))
    if (!address) return 0;
    unsigned char resident = 0;
    errno = 0;
    return mincore(address, 1, &resident) == -1 && errno == ENOMEM;
#else
    (void)address;
    return 0;
#endif
}

/* Copy only a complete published executable extent while its image borrow is live. */
static int pvm_mixed_arena_copy(void *handle, uint32_t offset, unsigned char *output,
        uint32_t length) {
#if defined(__linux__) && defined(__x86_64__)
    pvm_x86_arena *owner = handle;
    if (!owner || !output || length == 0 || (offset & 15) ||
            offset > owner->used || length > owner->used - offset) return 0;
    memcpy(output, (const unsigned char *)owner->executable + offset, length);
    return 1;
#elif defined(__aarch64__) && (defined(__APPLE__) || defined(__linux__))
    pvm_arm64_arena *owner = handle;
    if (!owner || !output || length == 0 || (offset & 3) ||
            offset > owner->used || length > owner->used - offset) return 0;
    memcpy(output, (const unsigned char *)owner->memory + offset, length);
    return 1;
#else
    (void)handle; (void)offset; (void)output; (void)length;
    return 0;
#endif
}

#endif
