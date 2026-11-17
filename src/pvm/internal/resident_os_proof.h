/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Test-only exact OS-release refusals and physical mapping observations.
 */
#ifndef PVM_RESIDENT_OS_PROOF_H
#define PVM_RESIDENT_OS_PROOF_H
#include <stddef.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/mman.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/mach_vm.h>
#endif

/* The production routines call these substitutes while holding the passed state's mutex. */
struct pvm_resident_state;
static int pvm_resident_witness_munmap(struct pvm_resident_state *, void *, size_t);
static void *pvm_resident_witness_calloc(struct pvm_resident_state *, size_t, size_t);
#define PVM_RESIDENT_WITNESS 1
#define PVM_RESIDENT_MUNMAP pvm_resident_witness_munmap
#define PVM_RESIDENT_CALLOC pvm_resident_witness_calloc
#include "resident_os.h"
#undef PVM_RESIDENT_MUNMAP
#undef PVM_RESIDENT_CALLOC

static int pvm_resident_witness_munmap(pvm_resident_state *state, void *data, size_t backing) {
    /* Refusal leaves the actual mapping present for the following lifetime observation. */
    if (state->refused_releases) {
        state->refused_releases--;
        errno = EBUSY;
        return -1;
    }
    return munmap(data, backing);
}
static void *pvm_resident_witness_calloc(pvm_resident_state *state, size_t count, size_t bytes) {
    /* Refuse the real cleanup-record allocation before mmap can run. */
    if (state->refused_records) {
        state->refused_records--;
        return NULL;
    }
    return calloc(count, bytes);
}
static pvm_resident_snapshot pvm_resident_witness_snapshot(pvm_resident_state *state) {
    /* Physical accounting includes records held after the final Nim drop. */
    pthread_mutex_lock(&state->lock);
    pvm_resident_snapshot result = state->observed;
    pthread_mutex_unlock(&state->lock);
    return result;
}
static void pvm_resident_witness_note_refusal(pvm_resident_state *state) {
    /* The Nim one-shot admission refusal acquires no mapping or cleanup record. */
    pthread_mutex_lock(&state->lock);
    state->observed.refusals++;
    pthread_mutex_unlock(&state->lock);
}
static void pvm_resident_witness_refuse_releases(pvm_resident_state *state, unsigned count) {
    /* Arm outside release; production serialization owns consumption. */
    pthread_mutex_lock(&state->lock);
    state->refused_releases = count;
    pthread_mutex_unlock(&state->lock);
}
static void pvm_resident_witness_refuse_record(pvm_resident_state *state) {
    /* Arm outside the factory; production serialization owns consumption. */
    pthread_mutex_lock(&state->lock);
    state->refused_records = 1;
    pthread_mutex_unlock(&state->lock);
}
static int pvm_resident_witness_mapped(void *data) {
    /* Return 1 mapped, 0 proved unmapped, -1 query failure; unknown cannot qualify retirement. */
#if defined(__APPLE__)
    mach_vm_address_t address = (mach_vm_address_t)(uintptr_t)data;
    mach_vm_address_t probe = address;
    mach_vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t status = mach_vm_region(mach_task_self(), &probe, &size,
        VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object);
    if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
    if (status == KERN_INVALID_ADDRESS) return 0;
    if (status != KERN_SUCCESS) return -1;
    return probe <= address && address - probe < size;
#else
    unsigned char resident = 0;
    errno = 0;
    if (mincore(data, 1, &resident) == 0) return 1;
    return errno == ENOMEM ? 0 : -1;
#endif
}
#endif
