# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Direct translation of pinned polkavm-common/src/operation.rs. Explicit division
## guards preserve source zero/overflow results in checked builds. The three i128
## products use inline C expressions because the pinned Nimony has no native i128.
## These are compiler integer primitives, with no Rust/reference execution linked.

proc divu*(lhs, rhs: uint32): uint32 {.inline.} =
  ## Unsigned zero divisor yields the maximum value.
  if rhs == 0: high(uint32) else: lhs div rhs

proc divu64*(lhs, rhs: uint64): uint64 {.inline.} =
  ## Same unsigned source rule at 64 bits.
  if rhs == 0: high(uint64) else: lhs div rhs

proc remu*(lhs, rhs: uint32): uint32 {.inline.} =
  ## Unsigned zero divisor preserves the dividend.
  if rhs == 0: lhs else: lhs mod rhs

proc remu64*(lhs, rhs: uint64): uint64 {.inline.} =
  ## Same unsigned remainder rule at 64 bits.
  if rhs == 0: lhs else: lhs mod rhs

proc divs*(lhs, rhs: int32): int32 {.inline.} =
  ## Handle both source exceptional cases before reaching the native division.
  if rhs == 0: -1'i32
  elif lhs == low(int32) and rhs == -1: lhs
  else: lhs div rhs

proc divs64*(lhs, rhs: int64): int64 {.inline.} =
  ## Signed minimum divided by minus one wraps to itself.
  if rhs == 0: -1'i64
  elif lhs == low(int64) and rhs == -1: lhs
  else: lhs div rhs

proc rems*(lhs, rhs: int32): int32 {.inline.} =
  ## Signed overflow remainder is zero; division by zero preserves the dividend.
  if rhs == 0: lhs
  elif lhs == low(int32) and rhs == -1: 0'i32
  else: lhs mod rhs

proc rems64*(lhs, rhs: int64): int64 {.inline.} =
  ## Same signed source remainder rule at 64 bits.
  if rhs == 0: lhs
  elif lhs == low(int64) and rhs == -1: 0'i64
  else: lhs mod rhs

proc mulh*(lhs, rhs: int32): int32 {.inline.} =
  ## Signed 32-bit operands fit a complete signed 64-bit product.
  int32((int64(lhs)*int64(rhs)) shr 32)

proc mulhsu*(lhs: int32, rhs: uint32): int32 {.inline.} =
  ## Signed-by-unsigned 32-bit operands also fit a signed 64-bit product.
  int32((int64(lhs)*int64(rhs)) shr 32)

proc mulhu*(lhs, rhs: uint32): uint32 {.inline.} =
  ## Unsigned product has the same upper bits as the source wrapping signed product.
  uint32((uint64(lhs)*uint64(rhs)) shr 32)

proc mulh64*(lhs, rhs: int64): int64
    {.importc: "faithful_mulh64", cdecl, header: "wide_arithmetic.h", raises: [].}
  ## Inline Clang i128 multiplication and arithmetic upper-half extraction.

proc mulhsu64*(lhs: int64, rhs: uint64): int64
    {.importc: "faithful_mulhsu64", cdecl, header: "wide_arithmetic.h", raises: [].}
  ## Inline signed-by-unsigned source i128 product.

proc mulhu64*(lhs, rhs: uint64): uint64
    {.importc: "faithful_mulhu64", cdecl, header: "wide_arithmetic.h", raises: [].}
  ## Inline unsigned source full-width product.
