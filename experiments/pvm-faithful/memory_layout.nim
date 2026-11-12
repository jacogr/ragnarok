# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Standard-memory placement translated from pinned common/abi.rs MemoryMapBuilder.
## Virtual region reservation rounds to 64 KiB; accessible extents round to the selected
## 4..64 KiB page. The heap starts after original, not rounded, writable data.

import std/assertions
import ./standard_memory
export standard_memory

type
  LayoutResult* = object
    ## A rejected geometry carries no partially usable memory map.
    case success: bool
    of true: value: MemoryLayout
    of false: discard

proc ok*(answer: LayoutResult): bool =
  ## Reject default results and all overcommitted/invalid-page geometries.
  answer.success

proc layout*(answer: LayoutResult): MemoryLayout =
  ## A complete validated map is required before mutable instance construction.
  assert answer.success
  answer.value

proc rounded(size: uint32, alignment: uint32): uint64 =
  ## Inputs are u32 and power-of-two alignment; widening preserves overflow detection.
  (uint64(size)+uint64(alignment)-1) and not(uint64(alignment)-1)

proc buildLayout*(page, roSize, rwSize, stackSize, auxSize: uint32,
    ro, rw: SharedBytes): LayoutResult =
  ## Match source admission/order, retaining supplied immutable module data after geometry succeeds.
  if page < 4096 or page > 65536 or (page and (page-1)) != 0: return LayoutResult(success: false)
  let roSpace = rounded(roSize, 65536)
  let rwSpace = rounded(rwSize, 65536)
  let stackSpace = rounded(stackSize, 65536)
  let auxSpace = rounded(auxSize, 65536)
  let roRounded = rounded(roSize, page)
  let rwRounded = rounded(rwSize, page)
  let stackRounded = rounded(stackSize, page)
  let auxRounded = rounded(auxSize, page)
  if roRounded > uint64(high(uint32)) or rwRounded > uint64(high(uint32)) or
      stackRounded > uint64(high(uint32)) or auxRounded > uint64(high(uint32)):
    return LayoutResult(success: false)
  var lowAddress = 65536'u64+roSpace+65536
  let rwAddress = lowAddress
  let heapBase = lowAddress+uint64(rwSize)
  lowAddress += rwSpace
  let heapSlack = lowAddress-heapBase
  lowAddress += 65536
  var highAddress = 0xffff0000'i64-int64(auxSpace)
  let auxAddress = highAddress
  highAddress -= 65536
  let stackHigh = highAddress
  highAddress -= int64(stackSpace)
  if int64(lowAddress) > highAddress: return LayoutResult(success: false)
  let maximumHeap = uint64(highAddress)-lowAddress+heapSlack
  LayoutResult(success: true, value: MemoryLayout(pageSize: page, roAddress: 65536,
    roSize: uint32(roRounded), rwAddress: uint32(rwAddress), rwSize: uint32(rwRounded),
    stackLow: uint32(stackHigh)-uint32(stackRounded), stackHigh: uint32(stackHigh),
    stackSize: uint32(stackRounded), auxAddress: uint32(auxAddress), auxSize: uint32(auxRounded),
    heapBase: uint32(heapBase), maxHeapSize: uint32(maximumHeap), ro: ro, rw: rw))
