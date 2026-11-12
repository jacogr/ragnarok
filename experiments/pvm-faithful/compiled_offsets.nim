# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## CompiledOffsets from pinned interpreter.rs:1390-1463. Epoch bits invalidate the
## instruction-to-handler map without touching each entry on ordinary cache resets.

import std/assertions
import ./plain_vector

type
  CompiledOffsets* = object
    ## Per-instance scalar offset table; zero/default storage is unallocated.
    entries: PlainVector[uint32]
    epoch, epochShift, validBit, indexMask: uint32
  CompiledOffset* = object
    ## Presence is distinct from handler index zero and from jump-target validity.
    present*, validJump*: bool
    target*: uint32

proc allocated*(offsets: CompiledOffsets): bool {.inline.} =
  ## Source is_allocated checks only whether the entries vector is empty.
  offsets.entries.len != 0

proc allocate*(offsets: var CompiledOffsets, length: uint32) =
  ## Partition each entry exactly like epoch_shift_for(len), including the validity bit.
  assert length > 0 and length <= 32'u32 * 1024 * 1024 + 1
  var power = 1'u32
  var shift = 1'u32
  while power < length * 4:
    power = power shl 1
    shift += 1
  offsets.entries.reset()
  offsets.entries.resizeZero(int(length))
  offsets.epoch = 1
  offsets.epochShift = shift
  offsets.validBit = power
  offsets.indexMask = power - 1

proc get*(offsets: CompiledOffsets, pc: uint32): CompiledOffset {.inline.} =
  ## Ignore absent/outdated entries without confusing an invalid jump with an absent entry.
  result = default(CompiledOffset)
  if uint64(pc) >= uint64(offsets.entries.len): return
  let entry = offsets.entries[int(pc)]
  if (entry shr offsets.epochShift) == offsets.epoch:
    result = CompiledOffset(present: true, validJump: (entry and offsets.validBit) != 0,
      target: entry and offsets.indexMask)

proc insert*(offsets: var CompiledOffsets, pc, target: uint32, validJump: bool) {.inline.} =
  ## Set the current epoch, target and independent jump-target-valid flag.
  assert target <= offsets.indexMask
  var entry = (offsets.epoch shl offsets.epochShift) or target
  if validJump: entry = entry or offsets.validBit
  offsets.entries[int(pc)] = entry

proc clear*(offsets: var CompiledOffsets): bool =
  ## Return true only when clearing rewrites an allocated table on epoch wraparound.
  if offsets.epoch < (high(uint32) shr offsets.epochShift):
    offsets.epoch += 1
    return false
  offsets.entries.zero()
  offsets.epoch = 1
  offsets.allocated

proc reset*(offsets: var CompiledOffsets) =
  ## Source reset drops entries while preserving the scalar partition metadata.
  offsets.entries.reset()
