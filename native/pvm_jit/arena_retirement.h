/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Exclusive OS-arena retirement. Providers embed this preallocated header first.
 * Physical failure keeps the arena owned and non-callable; final drop can transfer it to pending
 * cleanup without allocating. New factories drain or refuse while pending cleanup survives.
 */
#ifndef PVM_ARENA_RETIREMENT_H
#define PVM_ARENA_RETIREMENT_H
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#if defined(__linux__) || defined(__APPLE__)
#include <pthread.h>
#endif

typedef struct pvm_arena_retirement_state pvm_arena_retirement_state;
typedef struct pvm_arena_retirement_owner pvm_arena_retirement_owner;
struct pvm_arena_retirement_owner {
    pvm_arena_retirement_state *state;
    pvm_arena_retirement_owner *next;
    int (*release)(pvm_arena_retirement_owner *);
    unsigned retiring;
#ifdef PVM_NATIVE_RETIREMENT_WITNESS
    unsigned refused_unmaps;
    unsigned unmaps_before_refusal;
#endif
};
struct pvm_arena_retirement_state {
#if defined(__linux__) || defined(__APPLE__)
    pthread_mutex_t lock;
#else
    unsigned unsupported;
#endif
    pvm_arena_retirement_owner *pending;
#ifdef PVM_NATIVE_RETIREMENT_WITNESS
    unsigned acquisition_refusals;
#endif
};

static pvm_arena_retirement_state *pvm_arena_retirement_state_address(void) {
    /* The Nim binding calls this only through one canonical non-inline accessor. */
#if defined(__linux__) || defined(__APPLE__)
    static pvm_arena_retirement_state state = { .lock = PTHREAD_MUTEX_INITIALIZER };
#else
    static pvm_arena_retirement_state state = {0};
#endif
    return &state;
}
static void pvm_arena_lock(pvm_arena_retirement_state *state) {
    /* Unsupported providers cannot construct arenas and require no OS synchronization binding. */
#if defined(__linux__) || defined(__APPLE__)
    pthread_mutex_lock(&state->lock);
#else
    (void)state;
#endif
}
static void pvm_arena_unlock(pvm_arena_retirement_state *state) {
#if defined(__linux__) || defined(__APPLE__)
    pthread_mutex_unlock(&state->lock);
#else
    (void)state;
#endif
}
static void pvm_arena_retirement_init(pvm_arena_retirement_owner *owner,
        pvm_arena_retirement_state *state, int (*release)(pvm_arena_retirement_owner *)) {
    /* The arena allocation contains this header before any OS mapping can require cleanup. */
    owner->state = state;
    owner->next = NULL;
    owner->release = release;
    owner->retiring = 0;
}
static int pvm_arena_drain_locked(pvm_arena_retirement_state *state) {
    /* The failed head may remain while later records release; original authority never disappears. */
    pvm_arena_retirement_owner **link = &state->pending;
    while (*link) {
        pvm_arena_retirement_owner *owner = *link;
        pvm_arena_retirement_owner *next = owner->next;
        if (owner->release(owner)) *link = next;
        else link = &owner->next;
    }
    return state->pending == NULL;
}
static int pvm_arena_try_release(pvm_arena_retirement_owner *owner) {
    /* False retains exclusive authority in the caller, including any partially released alias pair. */
    if (!owner) return 1;
    pvm_arena_retirement_state *state = owner->state;
    pvm_arena_lock(state);
    owner->retiring = 1;
    int released = owner->release(owner);
    pvm_arena_unlock(state);
    return released;
}
static void pvm_arena_drop(pvm_arena_retirement_owner *owner) {
    /* Consume final authority into physical release or existing-record pending cleanup, never allocation. */
    if (!owner) return;
    pvm_arena_retirement_state *state = owner->state;
    pvm_arena_lock(state);
    owner->retiring = 1;
    if (!owner->release(owner)) {
        owner->next = state->pending;
        state->pending = owner;
    }
    pvm_arena_unlock(state);
}
#ifdef PVM_NATIVE_RETIREMENT_WITNESS
static void pvm_arena_refuse_unmaps(pvm_arena_retirement_owner *owner, unsigned count) {
    /* Test-only refusal is attached to this exact existing arena, under its real cleanup mutex. */
    if (!owner) return;
    pvm_arena_retirement_state *state = owner->state;
    pvm_arena_lock(state);
    owner->refused_unmaps = count;
    owner->unmaps_before_refusal = 0;
    pvm_arena_unlock(state);
}
static void pvm_arena_refuse_acquisition(pvm_arena_retirement_state *state, unsigned count) {
    /* A real first mapping is acquired before the factory fault; only its cleanup syscall refuses. */
    pvm_arena_lock(state);
    state->acquisition_refusals = count;
    pvm_arena_unlock(state);
}
static int pvm_arena_fail_acquisition_locked(pvm_arena_retirement_owner *owner) {
    /* Consume the process fault at the exact factory, with its physical ownership already recorded. */
    if (!owner->state->acquisition_refusals) return 0;
    owner->refused_unmaps = owner->state->acquisition_refusals;
    owner->state->acquisition_refusals = 0;
    return 1;
}
#endif
#endif
