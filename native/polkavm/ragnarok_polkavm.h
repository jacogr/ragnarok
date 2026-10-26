/* Copyright (c) 2026 Ragnarök contributors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Opaque invocation-local executor. Buffers are borrowed for one call, never retained.
 * Status: 0 success, 1 invalid input, 2 unavailable, 3 upstream failure,
 * 4 unsupported reentry, 5 caught unwind. Guest exits are carried only by event.
 * Caller owns one handle after create succeeds and must call destroy once.
 */
#ifndef RAGNAROK_POLKAVM_H
#define RAGNAROK_POLKAVM_H
#include <stddef.h>
#include <stdint.h>
typedef struct Rpvm Rpvm;
const char *rpvm_revision(void);
typedef struct RpvmEvent {
    uint64_t registers[13];
    uint32_t kind; /* 0 continued, 1 panic, 2 halt, 3 fault, 4 host */
    uint32_t pc; /* next PC for continued; causing PC for other outcomes */
    uint32_t detail; /* fault page or host identifier, selected by kind */
} RpvmEvent;
int rpvm_create(uint32_t backend, const uint8_t *code, size_t length, Rpvm **output);
int rpvm_destroy(Rpvm *handle);
int rpvm_reset(Rpvm *handle);
int rpvm_prepare(Rpvm *handle, uint32_t pc, const uint64_t *registers, size_t count);
int rpvm_step(Rpvm *handle, RpvmEvent *output);
int rpvm_page(Rpvm *handle, uint32_t address, uint32_t access,
              const uint8_t *data, size_t length);
int rpvm_read(Rpvm *handle, uint32_t address, uint8_t *data, size_t length);
#endif
