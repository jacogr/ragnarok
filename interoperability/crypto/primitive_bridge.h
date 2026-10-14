#ifndef RAGNAROK_CRYPTO_PRIMITIVE_BRIDGE_H
#define RAGNAROK_CRYPTO_PRIMITIVE_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
/* Synchronous primitive ABI only: no JAM domains, codec, state logic, callbacks or retained caller pointers. */
/* Hash borrowed raw bytes; write exactly 32 bytes on success, return 0 without output on bad arguments. */
int rc_blake2b256(const uint8_t *data, size_t length, uint8_t out[32]);
/* Hash borrowed bytes with legacy suffix 0x01; output owns its 32 bytes on success. */
int rc_keccak256(const uint8_t *data, size_t length, uint8_t out[32]);
/* Derive 32 public bytes from an exact borrowed seed; cleanse expanded private scratch before return. */
int rc_ed_public(const uint8_t seed[32], uint8_t out[32]);
/* Sign an exact message from a 32-byte seed; copy 64 signature bytes only on success, cleanse secret scratch. */
int rc_ed_sign(const uint8_t seed[32], const uint8_t *message, size_t length, uint8_t out[64]);
/* Return 1 for accepted fixed encodings/message, 0 for invalid signatures or missing nonempty input. */
int rc_ed_verify(const uint8_t public_key[32], const uint8_t signature[64], const uint8_t *message, size_t length);
/* Erase caller-owned storage explicitly; no pointer is retained. */
void rc_wipe(void *data, size_t length);
#endif
