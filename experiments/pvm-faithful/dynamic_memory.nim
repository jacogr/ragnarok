# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Translation of pinned PolkaVM interpreter.rs:829-1231, DynamicMemory and its
## scalar access paths. Mutable boxed pages live in the B-tree, with no snapshots.
## Guest accesses preserve checked-u32 endpoint faults and preflight both pages before
## a crossing store. Host operations use the public API's wider endpoint validation.
## Derived from PolkaVM, dual licensed under MIT OR Apache-2.0 (see PORTING.md).

import std/assertions
import ./page_map
import ./access
export access

type
  DynamicMemory* = object
    ## The source's mutable page map, configured power-of-two page size and mask.
    pages: PageMap
    pageSize, pageMask: uint32

proc reset*(memory: var DynamicMemory, pageSize: uint32) =
  ## Reset discards dynamic mappings, exactly as the upstream instance reset does.
  assert pageSize > 0 and (pageSize and (pageSize-1)) == 0
  memory.pages.clear()
  memory.pageSize = pageSize
  memory.pageMask = pageSize-1

func pageBase(memory: DynamicMemory, address: uint32): uint32 {.inline.} =
  ## Preserve the source's power-of-two page rounding.
  address and not memory.pageMask

proc accessible*(memory: DynamicMemory, address: uint32, length: int, writable: bool): bool =
  ## The public host contract permits an empty range and rejects a wrapped endpoint.
  assert length >= 0 and memory.pageSize > 0
  if uint64(length) > 0x100000000'u64-uint64(address): return false
  var position = uint64(address)
  let finish = position+uint64(length)
  while position < finish:
    # Upstream DynamicMemory checks each page with a separate B-tree lookup.
    let base = memory.pageBase(uint32(position))
    let page = memory.pages.find(base)
    if page == nil or (writable and page.readOnly): return false
    position = min(finish, uint64(base)+uint64(memory.pageSize))
  true

proc mapZero*(memory: var DynamicMemory, address, length: uint32, readOnly: bool): bool =
  ## zero_memory_with_memory_protection creates or clears complete aligned pages.
  assert memory.pageSize > 0
  if (address and memory.pageMask) != 0 or (length and memory.pageMask) != 0 or
      uint64(length) > 0x100000000'u64-uint64(address): return false
  var position = uint64(address)
  let finish = position+uint64(length)
  while position < finish:
    var created = false
    let page = memory.pages.insertPage(uint32(position), int(memory.pageSize), created)
    let data = page.data
    assert data != nil
    if not created: zeroMem(data, page.length)
    page.readOnly = readOnly
    position += uint64(memory.pageSize)
  true

proc protect*(memory: var DynamicMemory, address, length: uint32, readOnly: bool): bool =
  ## Source protection applies to every touched page, including unaligned partial pages.
  ## A later gap returns failure after any preceding pages have already changed protection.
  assert memory.pageSize > 0
  if uint64(length) > 0x100000000'u64 - uint64(address): return false
  var position = uint64(address)
  let finish = position + uint64(length)
  while position < finish:
    let base = memory.pageBase(uint32(position))
    let page = memory.pages.find(base)
    if page == nil: return false
    page.readOnly = readOnly
    position = uint64(base) + uint64(memory.pageSize)
  true

proc write*(memory: var DynamicMemory, address: uint32, input: openArray[byte]): bool =
  ## Host writes validate the complete writable range before modifying any page.
  if not memory.accessible(address, input.len, true): return false
  var offset = 0
  while offset < input.len:
    let position = uint64(address)+uint64(offset)
    let base = memory.pageBase(uint32(position))
    # Match the source entry lookup even though the preflight has proved presence.
    let page = memory.pages.insertPage(base, int(memory.pageSize))
    let data = page.data
    assert data != nil
    let within = int(position-uint64(base))
    let length = min(input.len-offset, page.length-within)
    copyMem(addr data[within], unsafeAddr input[offset], length)
    offset += length
  true

proc read*(memory: DynamicMemory, address: uint32, output: var openArray[byte]): bool =
  ## Host reads copy pagewise into caller storage; a later gap can leave a copied prefix.
  assert memory.pageSize > 0
  if uint64(output.len) > 0x100000000'u64-uint64(address): return false
  var offset = 0
  while offset < output.len:
    let position = uint64(address)+uint64(offset)
    let base = memory.pageBase(uint32(position))
    let page = memory.pages.find(base)
    if page == nil: return false
    let data = page.data
    assert data != nil
    let within = int(position-uint64(base))
    let length = min(output.len-offset, page.length-within)
    copyMem(addr output[offset], addr data[within], length)
    offset += length
  true

proc readBits[Width: static[int]](page: ptr Page, offset: int): uint64 {.inline.} =
  ## Decode an unaligned little-endian scalar after the caller proves its complete page extent.
  assert Width in [1, 2, 4, 8]
  assert offset >= 0 and offset <= page.length-Width
  let data = page.data
  assert data != nil
  result = 0
  for index in 0..<Width: result = result or (uint64(data[offset+index]) shl (index*8))

proc writeBits[Width: static[int]](page: ptr Page, offset: int, value: uint64) {.inline.} =
  ## Store the fixed-width low bytes only after the complete permission/range proof.
  assert Width in [1, 2, 4, 8]
  assert offset >= 0 and offset <= page.length-Width
  let data = page.data
  assert data != nil
  for index in 0..<Width: data[offset+index] = byte((value shr (index*8)) and 255)

proc endpoint(memory: DynamicMemory, address: uint32, width: int): Access {.inline.} =
  ## Upstream checked_add faults the last page if absent, otherwise traps, on u32 overflow.
  assert width in [1, 2, 4, 8]
  if uint64(address)+uint64(width) > uint64(high(uint32)):
    let base = memory.pageBase(high(uint32))
    if memory.pages.find(base) == nil: return Access(kind: AccessKind.Segfault, page: base)
    return Access(kind: AccessKind.Trap)
  Access(kind: AccessKind.Ok)

proc load*[Width: static[int]](memory: DynamicMemory, address: uint32): Access {.inline.} =
  ## Mirror DynamicMemory::load_impl, including the two-entry B-tree range lookup.
  assert Width in [1, 2, 4, 8] and memory.pageSize >= 8
  let checked = endpoint(memory, address, Width)
  if checked.kind != AccessKind.Ok: return checked
  let first = memory.pageBase(address)
  let last = memory.pageBase(address+uint32(Width)-1)
  if first == last:
    let page = memory.pages.find(first)
    if page == nil: return Access(kind: AccessKind.Segfault, page: first)
    return Access(kind: AccessKind.Ok, value: readBits[Width](page, int(address-first)))
  var cursor = memory.pages.lowerBound(first)
  var firstKey = 0'u32
  var lastKey = 0'u32
  let low = cursor.next(last, firstKey)
  let high = cursor.next(last, lastKey)
  if low == nil: return Access(kind: AccessKind.Segfault, page: first)
  if high == nil:
    return Access(kind: AccessKind.Segfault, page: (if firstKey == first: last else: first))
  let lowData = low.data
  let highData = high.data
  assert lowData != nil and highData != nil and firstKey == first and lastKey == last
  let lowLength = int(last-address)
  var value = 0'u64
  for index in 0..<Width:
    let octet = if index < lowLength: lowData[int(address-first)+index] else: highData[
        index-lowLength]
    value = value or (uint64(octet) shl (index*8))
  Access(kind: AccessKind.Ok, value: value)

proc store*[Width: static[int]](memory: var DynamicMemory, address: uint32,
    value: uint64): Access {.inline.} =
  ## Mirror DynamicMemory::store_impl; a missing/read-only second page cannot expose a partial write.
  assert Width in [1, 2, 4, 8] and memory.pageSize >= 8
  let checked = endpoint(memory, address, Width)
  if checked.kind != AccessKind.Ok: return checked
  let first = memory.pageBase(address)
  let last = memory.pageBase(address+uint32(Width)-1)
  if first == last:
    let page = memory.pages.find(first)
    if page == nil: return Access(kind: AccessKind.Segfault, page: first)
    if page.readOnly: return Access(kind: AccessKind.Segfault, page: first, readOnly: true)
    writeBits[Width](page, int(address-first), value)
    return Access(kind: AccessKind.Ok)
  var cursor = memory.pages.lowerBound(first)
  var firstKey = 0'u32
  var lastKey = 0'u32
  let low = cursor.next(last, firstKey)
  let high = cursor.next(last, lastKey)
  if low == nil: return Access(kind: AccessKind.Segfault, page: first)
  if high == nil:
    return Access(kind: AccessKind.Segfault, page: (if firstKey == first: last else: first))
  if low.readOnly or high.readOnly:
    return Access(kind: AccessKind.Segfault, page: (if low.readOnly: first else: last),
        readOnly: true)
  let lowData = low.data
  let highData = high.data
  assert lowData != nil and highData != nil and firstKey == first and lastKey == last
  let lowLength = int(last-address)
  for index in 0..<Width:
    let octet = byte((value shr (index*8)) and 255)
    if index < lowLength: lowData[int(address-first)+index] = octet
    else: highData[index-lowLength] = octet
  Access(kind: AccessKind.Ok)

proc zero*(memory: var DynamicMemory, address, length: uint32): bool =
  ## Source zero_memory without a protection change preflights all pages before clearing any bytes.
  if not memory.accessible(address, int(length), true): return false
  var position = uint64(address)
  let finish = position + uint64(length)
  while position < finish:
    let base = memory.pageBase(uint32(position))
    let page = memory.pages.insertPage(base, int(memory.pageSize))
    let data = page.data
    assert data != nil
    let within = int(position - uint64(base))
    let count = int(min(finish - position, uint64(memory.pageSize) - uint64(within)))
    zeroMem(addr data[within], count)
    position += uint64(count)
  true
