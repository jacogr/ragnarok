/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Private OS witnesses for partial alias release and allocation-free final-drop retirement.
 */
#ifndef PVM_ARENA_RETIREMENT_PROOF_H
#define PVM_ARENA_RETIREMENT_PROOF_H
#include "mixed_arena_proof.h"
#if defined(__linux__) && defined(__x86_64__)
#define proof_arena pvm_x86_arena
#define proof_create pvm_x86_arena_create_owned
#define proof_destroy pvm_x86_arena_destroy
#define proof_try_destroy pvm_x86_arena_try_destroy
#define proof_refuse pvm_x86_arena_refuse_unmaps
#define proof_publish pvm_x86_arena_publish
#define proof_call pvm_x86_arena_call
#elif defined(__aarch64__) && (defined(__APPLE__) || defined(__linux__))
#define proof_arena pvm_arm64_arena
#define proof_create pvm_arm64_arena_create_owned
#define proof_destroy pvm_arm64_arena_destroy
#define proof_try_destroy pvm_arm64_arena_try_destroy
#define proof_refuse pvm_arm64_arena_refuse_unmaps
#define proof_publish pvm_arm64_arena_publish
#define proof_call pvm_arm64_arena_call
#endif

static int pvm_arena_retirement_proof(pvm_arena_retirement_state *state) {
    /* Every failed stage keeps cleanup authority; return a diagnostic instead of aborting in C. */
#ifdef proof_arena
    int stage = 1;
    proof_arena *owner = proof_create(state);
    if (!owner || owner->retirement.retiring) goto failed;
    void *rx = pvm_mixed_arena_address(owner);
    void *rw = pvm_mixed_arena_writable_address(owner);
    if (!rx || !rw) goto failed;
#if defined(__x86_64__)
    const unsigned char leaf[] = { 0xc3 };
#else
    const uint32_t leaf[] = { UINT32_C(0xd65f03c0) };
#endif
    uint64_t registers[13] = {0};
    stage = 2;
    if (proof_publish(owner, leaf, 1) != 0) goto failed;
    proof_refuse(owner, 100);
#if defined(__linux__)
    /* Real RW release succeeds first; only the distinct RX alias remains owned after refusal. */
    pvm_arena_lock(state);
    owner->retirement.unmaps_before_refusal = 1;
    pvm_arena_unlock(state);
#endif
    stage = 3;
    if (proof_try_destroy(owner) != 0) { owner = NULL; goto failed; }
    if (!owner->retirement.retiring || pvm_mixed_arena_unmapped(rx)) goto failed;
#if defined(__linux__)
    if (owner->mapped != 2 || !pvm_mixed_arena_unmapped(rw)) goto failed;
#endif
    stage = 4;
    if (proof_publish(owner, leaf, 1) != -1 || proof_call(owner, 0, registers) != 0) goto failed;
    proof_refuse(owner, 0);
    stage = 5;
    if (!proof_try_destroy(owner)) goto failed;
    owner = NULL;
    if (!pvm_mixed_arena_unmapped(rx) || !pvm_mixed_arena_unmapped(rw)) goto failed;

    /* Final drop consumes the existing record into pending cleanup, and admission refuses meanwhile. */
    stage = 6;
    owner = proof_create(state);
    if (!owner || owner->retirement.retiring) goto failed;
    rx = pvm_mixed_arena_address(owner);
    rw = pvm_mixed_arena_writable_address(owner);
    proof_refuse(owner, 100);
    proof_destroy(owner);
    owner = NULL;
    stage = 7;
    if (pvm_mixed_arena_unmapped(rx) || pvm_mixed_arena_unmapped(rw)) goto failed;
    owner = proof_create(state);
    if (owner) goto failed;
    pvm_arena_lock(state);
    int pending = state->pending != NULL;
    /* Only the cleanup owner touches this transferred record; no dangling observer dereference. */
    for (pvm_arena_retirement_owner *at = state->pending; at; at = at->next) at->refused_unmaps = 0;
    int drained = pvm_arena_drain_locked(state);
    pvm_arena_unlock(state);
    stage = 8;
    if (!pending || !drained || !pvm_mixed_arena_unmapped(rx) || !pvm_mixed_arena_unmapped(rw))
        goto failed;
    stage = 9;
    owner = proof_create(state);
    if (!owner || owner->retirement.retiring) goto failed;
    proof_destroy(owner);
    return 0;
failed:
    if (owner) { proof_refuse(owner, 0); proof_destroy(owner); }
    pvm_arena_lock(state);
    for (pvm_arena_retirement_owner *at = state->pending; at; at = at->next) at->refused_unmaps = 0;
    pvm_arena_drain_locked(state);
    pvm_arena_unlock(state);
    return stage;
#else
    (void)state;
    return -1;
#endif
}
#endif
