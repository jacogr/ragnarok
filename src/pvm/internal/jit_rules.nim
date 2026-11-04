# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Pure GP opcode descriptions and the common scalar lowering subset used by native emitters.
## These copied values carry no backend, source owner, invocation state or machine encoding.

type
  IndirectMemoryKind* {.pure.} = enum
    ## Stores truncate to the access width; loads zero-extend or sign-extend to a full register.
    Store, UnsignedLoad, SignedLoad
  IndirectMemoryAccess* = object
    ## One validated indirect opcode's byte width and register transfer semantics.
    width*: uint32
    kind*: IndirectMemoryKind

func indirectMemoryAccess*(opcode: range[120..130]): IndirectMemoryAccess {.inline.} =
  ## Callers prove family membership before conversion; unrelated opcodes have no default width.
  let width = case opcode
    of 120, 124, 125: 1'u32
    of 121, 126, 127: 2'u32
    of 122, 128, 129: 4'u32
    of 123, 130: 8'u32
  let kind = case opcode
    of 120..123: IndirectMemoryKind.Store
    of 125, 127, 129: IndirectMemoryKind.SignedLoad
    of 124, 126, 128, 130: IndirectMemoryKind.UnsignedLoad
  IndirectMemoryAccess(width: width, kind: kind)

func supportedScalarOpcode*(opcode: byte): bool {.inline.} =
  ## Both baseline emitters lower this exact non-exiting scalar subset without optional extensions.
  ## Architecture wrappers retain the boundary for later explicit capability differences.
  opcode in {20'u8, 51, 100, 107..110, 131..143, 149..154, 158, 160,
      190..192, 197..202, 207..217, 222..226}
