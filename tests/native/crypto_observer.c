// Copyright (c) 2026 Ragnarök contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

// Instruments the maintained crypto ABI for native tests. Exposes call/wipe observations and
// controlled backend refusals to ownership and failure tests.

/* Test-only observation/fault layer; production links the unmodified maintained primitive bridge. */
#include "primitive_bridge.h"

/* The test build renames only project bridge symbols; upstream sources remain pristine. */
void rc_real_wipe(void *, size_t);
int rc_real_blake2b256(const uint8_t *, size_t, uint8_t *);
int rc_real_keccak256(const uint8_t *, size_t, uint8_t *);
int rc_real_ed_public(const uint8_t *, uint8_t *);
int rc_real_ed_sign(const uint8_t *, const uint8_t *, size_t, uint8_t *);

/* Observation retains an address identity, never an ARC reference or a pointer read after free. */
static void *target;
static size_t target_length;
static int calls, before_nonzero, after_zero, failures;
/* Sequential fault tests count attempted Blake2b calls and may refuse after a known successful prefix. */
static int blake_calls, blake_remaining = -1;

/* Reset before each isolated fixture; only the wipe callback may inspect the still-live target. */
void ro_watch(void *address, size_t length) {
    target = address;
    target_length = length;
    calls = before_nonzero = after_zero = 0;
}
/* Expose copied counters only, never secret storage or an address. */
int ro_calls(void) { return calls; }
int ro_before_nonzero(void) { return before_nonzero; }
int ro_after_zero(void) { return after_zero; }
/* Fault flags apply only to the observer-linked sequential test adapter. */
void ro_fail(int flags) {
    failures = flags;
    blake_calls = 0;
    blake_remaining = -1;
}
/* Refuse after a bounded number of successful calls, allowing cleanup after completed child hashes to be tested. */
void ro_blake_after(int successful) {
    failures = 0;
    blake_calls = 0;
    blake_remaining = successful;
}
/* Expose copied attempt counts to prove all preflight failures occur before cryptographic work. */
int ro_blake_calls(void) { return blake_calls; }

/* Inspect the live object before and after the real explicit cleanse, before the destructor can free it. */
void rc_wipe(void *address, size_t length) {
    int matches = address == target && length == target_length;
    /* Nonzero public fixture bytes prove the callback targets the original storage, not a cleared temporary. */
    if (matches) {
        const uint8_t *bytes = address;
        ++calls;
        for (size_t i = 0; i < length; ++i) {
            if (bytes[i] != 0) { ++before_nonzero; break; }
        }
    }
    rc_real_wipe(address, length);
    /* All reads still occur inside the wipe call while the allocation is alive. */
    if (matches) {
        const uint8_t *bytes = address;
        int zero = 1;
        for (size_t i = 0; i < length; ++i) {
            if (bytes[i] != 0) { zero = 0; break; }
        }
        if (zero) ++after_zero;
    }
}
/* Inject a backend refusal without modifying output; successful calls use exactly the production bridge. */
int rc_blake2b256(const uint8_t *data, size_t length, uint8_t out[32]) {
    ++blake_calls;
    /* Both immediate and delayed refusals leave the caller output untouched. */
    if ((failures & 1) || blake_remaining == 0) return 0;
    /* A negative counter disables delayed refusal; only a positive budget is decremented. */
    if (blake_remaining > 0) --blake_remaining;
    return rc_real_blake2b256(data, length, out);
}
/* Keccak refusal is independent of Blake2b and preserves the legacy production implementation. */
int rc_keccak256(const uint8_t *data, size_t length, uint8_t out[32]) {
    return failures & 2 ? 0 : rc_real_keccak256(data, length, out);
}
/* Public derivation failures must not publish a default key. */
int rc_ed_public(const uint8_t seed[32], uint8_t out[32]) {
    return failures & 4 ? 0 : rc_real_ed_public(seed, out);
}
/* Signing failures must not publish a zero/default signature. */
int rc_ed_sign(const uint8_t seed[32], const uint8_t *data, size_t length, uint8_t out[64]) {
    return failures & 8 ? 0 : rc_real_ed_sign(seed, data, length, out);
}
