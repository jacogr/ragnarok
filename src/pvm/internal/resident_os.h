/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Private anonymous mappings with retained cleanup authority on OS refusal.
 * Only resident_bytes binds this header's factory, view and release operations.
 */
#ifndef PVM_RESIDENT_OS_H
#define PVM_RESIDENT_OS_H

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>

#ifndef PVM_RESIDENT_MUNMAP
#define PVM_RESIDENT_MUNMAP(state, data, backing) munmap(data, backing)
#endif
#ifndef PVM_RESIDENT_CALLOC
#define PVM_RESIDENT_CALLOC(state, count, bytes) calloc(count, bytes)
#endif

/* Allocate this record before mmap: final release must never allocate to retain a failed unmap. */
typedef struct pvm_resident_owner {
    void *data;
    size_t logical, backing;
    struct pvm_resident_owner *next;
} pvm_resident_owner;

/* Status 0 is success, 1 invalid size, 2 local resource/cleanup refusal. */
typedef struct {
    void *data;
    size_t logical, backing;
    int status;
    pvm_resident_owner *authority;
} pvm_resident_allocation;

/* A borrowed record carries no release authority and cannot outlive its exclusive owner. */
typedef struct {
    void *data;
    size_t logical, backing;
} pvm_resident_view;

#ifdef PVM_RESIDENT_WITNESS
/* Physical charges survive Nim last-drop until actual release; test faults share this same state. */
typedef struct {
    uint64_t acquisitions, releases, refusals, logicalBytes, mappedBytes;
} pvm_resident_snapshot;
#endif

/* Admission pauses while cleanup remains pending, bounded by owners live at the first failed release.
 * Pass this state explicitly: foreign inline wrappers can be emitted in different translation units. */
typedef struct pvm_resident_state {
    pthread_mutex_t lock;
    pvm_resident_owner *pending;
#ifdef PVM_RESIDENT_WITNESS
    pvm_resident_snapshot observed;
    unsigned refused_releases, refused_records;
#endif
} pvm_resident_state;

static pvm_resident_state *pvm_resident_state_address(void) {
    /* Only the binding's non-inline address accessor calls this translation-unit-local singleton. */
    static pvm_resident_state state = { .lock = PTHREAD_MUTEX_INITIALIZER };
    return &state;
}

static pvm_resident_allocation pvm_resident_refused(int status) {
    /* A refusal owns no record, including after an unusual zero-address mmap success. */
    pvm_resident_allocation result = {NULL, 0, 0, status, NULL};
    return result;
}

static int pvm_resident_retire_locked(pvm_resident_state *state, pvm_resident_owner *owner) {
    /* The record retains the original physical extent independently of borrowed/cached Nim metadata. */
    if (owner->backing == 0 || PVM_RESIDENT_MUNMAP(state, owner->data, owner->backing) != 0) return 0;
#ifdef PVM_RESIDENT_WITNESS
    state->observed.releases++;
    state->observed.logicalBytes -= owner->logical;
    state->observed.mappedBytes -= owner->backing;
#endif
    free(owner);
    return 1;
}

static int pvm_resident_drain_locked(pvm_resident_state *state) {
    /* Failed records stay linked; successful records retire exactly once without allocation. */
    pvm_resident_owner **link = &state->pending;
    while (*link) {
        pvm_resident_owner *owner = *link;
        pvm_resident_owner *next = owner->next;
        if (pvm_resident_retire_locked(state, owner)) *link = next;
        else link = &owner->next;
    }
    return state->pending == NULL;
}

static int pvm_resident_drain(pvm_resident_state *state) {
    /* An explicit retry and factory admission use the same serialized cleanup owner. */
    pthread_mutex_lock(&state->lock);
    int released = pvm_resident_drain_locked(state);
    pthread_mutex_unlock(&state->lock);
    return released;
}

static void pvm_resident_drop(pvm_resident_state *state, pvm_resident_owner *owner) {
    /* Consume exclusive authority once. A failed unmap transfers it to the process-lifetime cleanup owner. */
    if (!owner) return;
    pthread_mutex_lock(&state->lock);
    if (!pvm_resident_retire_locked(state, owner)) {
        owner->next = state->pending;
        state->pending = owner;
    }
    pthread_mutex_unlock(&state->lock);
}

static pvm_resident_view pvm_resident_borrow(pvm_resident_owner *owner) {
    /* The caller retains this non-pending exclusive record for the entire synchronous borrow. */
    pvm_resident_view result = {NULL, 0, 0};
    if (owner) {
        result.data = owner->data;
        result.logical = owner->logical;
        result.backing = owner->backing;
    }
    return result;
}

static pvm_resident_allocation pvm_resident_map(pvm_resident_state *state, size_t logical) {
    /* Empty success performs no allocation, cleanup attempt or syscall. */
    if (logical == 0) return pvm_resident_refused(0);
    long queried = sysconf(_SC_PAGESIZE);
    if (queried <= 0) {
#ifdef PVM_RESIDENT_WITNESS
        pthread_mutex_lock(&state->lock);
        state->observed.refusals++;
        pthread_mutex_unlock(&state->lock);
#endif
        return pvm_resident_refused(2);
    }
    size_t page = (size_t)queried;
    size_t remainder = logical % page;
    size_t extra = remainder ? page - remainder : 0;
    if (logical > SIZE_MAX - extra) return pvm_resident_refused(1);
    size_t backing = logical + extra;
    pthread_mutex_lock(&state->lock);
    if (!pvm_resident_drain_locked(state)) {
#ifdef PVM_RESIDENT_WITNESS
        state->observed.refusals++;
#endif
        pthread_mutex_unlock(&state->lock);
        return pvm_resident_refused(2);
    }
    pvm_resident_owner *owner = PVM_RESIDENT_CALLOC(state, 1, sizeof(*owner));
    if (!owner) {
#ifdef PVM_RESIDENT_WITNESS
        state->observed.refusals++;
#endif
        pthread_mutex_unlock(&state->lock);
        return pvm_resident_refused(2);
    }
    void *data = mmap(NULL, backing, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (data == MAP_FAILED) {
        free(owner);
#ifdef PVM_RESIDENT_WITNESS
        state->observed.refusals++;
#endif
        pthread_mutex_unlock(&state->lock);
        return pvm_resident_refused(2);
    }
    owner->data = data;
    owner->logical = logical;
    owner->backing = backing;
#ifdef PVM_RESIDENT_WITNESS
    state->observed.acquisitions++;
    state->observed.logicalBytes += logical;
    state->observed.mappedBytes += backing;
#endif
    if (data == NULL) {
        /* Nil stays reserved for an empty borrow; preserve even address-zero cleanup on OS refusal. */
        if (!pvm_resident_retire_locked(state, owner)) {
            owner->next = state->pending;
            state->pending = owner;
        }
#ifdef PVM_RESIDENT_WITNESS
        state->observed.refusals++;
#endif
        pthread_mutex_unlock(&state->lock);
        return pvm_resident_refused(2);
    }
    pthread_mutex_unlock(&state->lock);
    pvm_resident_allocation result = {data, logical, backing, 0, owner};
    return result;
}

#endif
