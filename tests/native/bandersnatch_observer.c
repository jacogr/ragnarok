/* Test-only counters/faults wrap the maintained Rust ABI; production calls and upstream code are unchanged. */
#include "bridge.h"

static int key_new_calls, key_free_calls, setup_new_calls, setup_free_calls;
static int live_keys, live_setups, fail_flags, verify_calls;
/* Reset only between scopes after every real allocation has been released; live counters cannot be reset away. */
void bo_reset(int flags) {
    key_new_calls = key_free_calls = setup_new_calls = setup_free_calls = 0;
    fail_flags = flags;
    verify_calls = 0;
}
/* Read counters by value without exposing native addresses or inspecting secret/freed storage. */
int bo_key_news(void) { return key_new_calls; }
int bo_key_frees(void) { return key_free_calls; }
int bo_setup_news(void) { return setup_new_calls; }
int bo_setup_frees(void) { return setup_free_calls; }
int bo_live_keys(void) { return live_keys; }
int bo_live_setups(void) { return live_setups; }
/* Refusal leaves the initialized out pointer untouched, exactly as a failed production import does. */
uint32_t bo_key_new(const uint8_t *data, size_t length, void **out) {
    ++key_new_calls;
    if (fail_flags & 1) return 5;
    uint32_t status = bs_key_new(data, length, out);
    if (status == 0) ++live_keys;
    return status;
}
/* Actual native destruction still runs: an invalid double release must fail rather than be hidden by this observer. */
void bo_key_free(void *handle) {
    ++key_free_calls;
    if (handle) --live_keys;
    bs_key_free(handle);
}
/* Setup failures are independent of scalar imports; successful setups use the original pinned embedded SRS. */
uint32_t bo_setup_new(size_t capacity, void **out) {
    ++setup_new_calls;
    if (fail_flags & 2) return 5;
    uint32_t status = bs_setup_new(capacity, out);
    if (status == 0) ++live_setups;
    return status;
}
/* The original Rust allocator/destructor owns setup storage; this wrapper observes only call counts. */
void bo_setup_free(void *handle) {
    ++setup_free_calls;
    if (handle) --live_setups;
    bs_setup_free(handle);
}

/* Count/refuse commitment at the maintained ABI boundary, before any backend output is published. */
static int commit_calls;
void bo_commit_reset(void) { commit_calls = 0; }
int bo_commits(void) { return commit_calls; }
uint32_t bo_commit(const void *handle, const uint8_t *keys, size_t length, uint8_t *out) {
    ++commit_calls;
    if (fail_flags & 4) return 5;
    return bs_commit(handle, keys, length, out);
}

/* Observe/refuse proof verification without replacing any production proof or successful output. */
int bo_verifies(void) { return verify_calls; }
uint32_t bo_ring_verify(const void *handle, const uint8_t *root, const uint8_t *proof, size_t proof_len,
                       const uint8_t *input, size_t input_len, const uint8_t *ad, size_t ad_len, uint8_t *out) {
    ++verify_calls;
    if (fail_flags & 8) return 5;
    return bs_ring_verify(handle, root, proof, proof_len, input, input_len, ad, ad_len, out);
}
