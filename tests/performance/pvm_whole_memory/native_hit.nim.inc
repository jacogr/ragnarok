# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Private owned source fragment; the projector removes exactly these three comment lines.
  # Common native access uses only real writer chunks admitted by the original checked helper.
  var misses: seq[int] = @[]
  emitImmediate(builder.words, 1, uint64(item.x) and 0xffffffff'u64)
  case access.base
  of MemoryBase.A: builder.words.add(0x0b010001'u32 or (reg(slots.aIndex) shl 5))
  of MemoryBase.B: builder.words.add(0x0b010001'u32 or (reg(slots.bIndex) shl 5))
  else: discard
  if not access.isLoad:
    if access.usesImmediate: emitImmediate(builder.words, 2, uint64(item.y))
    else: builder.words.add(0xaa0003e2'u32 or (reg(slots.aIndex) shl 16))
  emitImmediate(builder.words, 3, 65536)
  builder.words.add(0xeb03003f'u32) # CMP X1,X3; protected-prefix refusals always use original ordering.
  misses.add(conditional(builder.words, 3))
  emitImmediate(builder.words, 3, 0xffffffff'u64-uint64(access.width))
  builder.words.add(0xeb03003f'u32)
  misses.add(conditional(builder.words, 8))
  emitImmediate(builder.words, 3, 511)
  builder.words.add(0x8a030023'u32) # AND X3,X1,X3 supplies the complete chunk offset.
  builder.words.add(0xf100007f'u32 or (uint32(512-int(access.width)) shl 10))
  misses.add(conditional(builder.words, 8))
  loadWord(builder.words, 12, 31, 96)
  builder.words.add(0xd349fc2d'u32) # LSR X13,X1,#9: exact physical page/chunk key.
  loadWord(builder.words, 14, 12, (if access.isLoad: 160 else: 176))
  builder.words.add(0xeb0e01bf'u32) # CMP X13,X14.
  misses.add(conditional(builder.words, 1))
  loadWord(builder.words, 14, 12, (if access.isLoad: 168 else: 184))
  builder.words.add(0xf10001df'u32) # CMP X14,#0; a retired pointer never conveys authority.
  misses.add(conditional(builder.words, 0))
  loadWord(builder.words, 13, 12, 192)
  builder.words.add(0xf10001bf'u32)
  misses.add(conditional(builder.words, 0))
  loadWord(builder.words, 13, 13, 0) # Current shared alias/snapshot revocation generation.
  loadWord(builder.words, 0, 12, (if access.isLoad: 200 else: 208))
  builder.words.add(0xeb0001bf'u32) # CMP X13,X0 precedes every chunk-pointer dereference.
  misses.add(conditional(builder.words, 1))
  builder.words.add(0x8b0301ce'u32) # ADD X14,X14,X3, after full-span and epoch guards.
  let operation = if access.isLoad:
    (if access.width == 1: 0x39400000'u32 elif access.width == 2: 0x79400000'u32
     elif access.width == 4: 0xb9400000'u32 else: 0xf9400000'u32)
    else:
      (if access.width == 1: 0x39000000'u32 elif access.width == 2: 0x79000000'u32
       elif access.width == 4: 0xb9000000'u32 else: 0xf9000000'u32)
  builder.words.add(operation or (14'u32 shl 5) or (if access.isLoad: 0'u32 else: 2'u32))
  let counter = if access.isLoad: 216 else: 224
  loadWord(builder.words, 13, 12, counter)
  builder.words.add(0x910005ad'u32) # ADD X13,X13,#1 counts a real native direct access.
  storeWord(builder.words, 13, 12, counter)
  let directDone = branch(builder.words)
  for miss in misses: patchBranch(builder.words, miss, builder.words.len)
  # Every miss retains the unchanged original complete helper/preflight/COW/failure path.
  setPc(builder.words, uint64(item.address))