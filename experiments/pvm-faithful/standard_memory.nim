# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Port of pinned PolkaVM interpreter.rs:99-827 (StandardMemory). Read-only and
## initial writable data share immutable module byte owners. Mutable RW/stack/aux
## vectors grow lazily with the source's 4096-byte reservation policy. Instance reset
## clears initialized mutable lengths while retaining capacities. Guest stores do
## not write auxiliary memory; host writes may. No page snapshots are constructed.

import std/assertions
import ./[buffer, access, shared_bytes]
export access, shared_bytes

type
  MemoryLayout* = object
    ## Validated module memory map; addresses and sizes have the source's u32 domains.
    pageSize*, roAddress*, rwAddress*, stackLow*, stackHigh*, auxAddress*: uint32
    roSize*, rwSize*, stackSize*, auxSize*, heapBase*, maxHeapSize*: uint32
    ro*, rw*: SharedBytes
  StandardMemory* = object
    ## Same region/initial-data separation as upstream; mutable vectors are exclusive.
    roData, rwOriginal: SharedBytes
    roSize, rwSize, stackSize, auxSize: int
    roAddress, rwAddress, stackLow, stackHigh, stackResidentLow, auxAddress: uint32
    heapSize: uint32
    maximumAllocation, memoryLimit: uint64
    rw, stack, aux: Bytes

proc reset*(memory: var StandardMemory, layout: MemoryLayout) =
  ## Translation of StandardMemory::reset_memory; no eager initialization of declared RAM.
  memory.roData = layout.ro
  memory.rwOriginal = layout.rw
  memory.roSize = int(layout.roSize)
  memory.rwSize = int(layout.rwSize)
  memory.stackSize = int(layout.stackSize)
  memory.auxSize = int(layout.auxSize)
  memory.heapSize = 0
  memory.rw.clear()
  memory.stack.clear()
  memory.aux.clear()
  memory.roAddress = layout.roAddress
  memory.rwAddress = layout.rwAddress
  memory.stackLow = layout.stackLow
  memory.stackHigh = layout.stackHigh
  memory.stackResidentLow = layout.stackHigh
  memory.auxAddress = layout.auxAddress

proc newStandardMemory*(layout: MemoryLayout): StandardMemory =
  ## Bind genuine immutable data owners before any access; allocation limits default to usize::MAX.
  var memory = StandardMemory(roData: layout.ro, rwOriginal: layout.rw,
    maximumAllocation: high(uint64), memoryLimit: high(uint64))
  memory.reset(layout)
  move(memory)

proc setLimits*(memory: var StandardMemory, maximumAllocation, total: uint64) =
  ## Match the two public interpreter allocation limits without changing already resident bytes.
  memory.maximumAllocation = maximumAllocation
  memory.memoryLimit = total

func nextPower(value: int): int =
  ## The source rounds reservation up to a power of two, independently of initialized length.
  assert value > 0 and uint64(value) <= 0x100000000'u64
  var power = 1
  while power < value: power = power shl 1
  power

proc reserve(buffer: var Bytes, required: int, maximum, limit: uint64, other: int): bool =
  ## Translation of reserve_memory; retain the source's capacity-based budget accounting.
  if buffer.capacity >= required: return true
  let used = uint64(other)+uint64(buffer.capacity)
  if uint64(required) > maximum or used >= limit: return false
  let target = min(uint64(max(nextPower(required), 4096)), maximum)
  let extra = target-uint64(buffer.capacity)
  if extra > limit-used: return false
  assert target <= uint64(high(int))
  buffer.reserveExact(int(target))
  buffer.capacity >= required

proc resizeRw(memory: var StandardMemory, required: int): bool =
  ## Populate the source-data prefix only as RAM becomes resident, then zero the new tail.
  if not reserve(memory.rw, required, memory.maximumAllocation, memory.memoryLimit,
      memory.stack.capacity+memory.aux.capacity): return false
  let length = min(memory.rw.capacity, ((required+4095) div 4096)*4096)
  let oldLength = memory.rw.len
  let copiedEnd = min(length, memory.rwOriginal.len)
  # Reserve proves storage exists; explicitly initialize the prefix before publishing the new length.
  memory.rw.len = length
  if oldLength < copiedEnd:
    memory.rwOriginal.copyInto(oldLength, memory.rw, oldLength, copiedEnd-oldLength)
  let zeroStart = max(oldLength, copiedEnd)
  if zeroStart < length: memory.rw.fillZero(zeroStart, length-zeroStart)
  true

proc resizeStack(memory: var StandardMemory, required: int): bool =
  ## Rust allocates a new downward-growing stack vector and copies its prior suffix.
  var next = default(Bytes)
  if not reserve(next, required, memory.maximumAllocation, memory.memoryLimit,
      memory.rw.capacity+memory.aux.capacity): return false
  let length = min(next.capacity, memory.stackSize)
  let newSpace = length-memory.stack.len
  next.len = length
  next.fillZero(0, newSpace)
  next.copyWithinOwner(newSpace, memory.stack, 0, memory.stack.len)
  memory.stack = move(next)
  memory.stackResidentLow = memory.stackHigh-uint32(memory.stack.len)
  true

proc resizeAux(memory: var StandardMemory, required: int): bool =
  ## Auxiliary input uses its own lazy zero-filled vector and the same reservation policy.
  if not reserve(memory.aux, required, memory.maximumAllocation, memory.memoryLimit,
      memory.rw.capacity+memory.stack.capacity): return false
  let length = min(memory.aux.capacity, ((required+4095) div 4096)*4096)
  memory.aux.resizeZero(length)
  true

proc prepareStack(memory: var StandardMemory, address: uint32, length: int): Access =
  ## Validate the complete descending stack span before any write or allocation.
  if uint64(address)+uint64(length) > uint64(memory.stackHigh): return Access(kind: AccessKind.Trap)
  let required = int(uint64(memory.stackHigh)-uint64(address))
  if required > memory.stack.len:
    if required > memory.stackSize: return Access(kind: AccessKind.Trap)
    if not memory.resizeStack(required): return Access(kind: AccessKind.MemoryLimit)
  Access(kind: AccessKind.Ok, value: uint64(address)-uint64(memory.stackResidentLow))

proc copyPart(source: Bytes, first, length: int, output: var openArray[byte], at: int) =
  ## Copy one proven initialized source interval without constructing an intermediate sequence.
  if length > 0:
    assert at >= 0 and at <= output.len and length <= output.len-at
    source.copyTo(first, output.toOpenArray(at, at+length-1))

proc copyPart(source: SharedBytes, first, length: int, output: var openArray[byte], at: int) =
  ## Read an immutable retained module slice without copying its parent bytes.
  if length > 0:
    assert at >= 0 and at <= output.len and length <= output.len-at
    source.copyTo(first, output.toOpenArray(at, at+length-1))

proc read*(memory: StandardMemory, address: uint32, output: var openArray[byte]): bool =
  ## Mirror StandardMemory::read_memory_into, including lazy initial-data and zero ranges.
  let length = output.len
  var initialized = 0
  if address >= memory.auxAddress:
    let first = int(address-memory.auxAddress)
    if first+length > memory.auxSize: return false
    initialized = min(first+length, memory.aux.len)-min(first, memory.aux.len)
    copyPart(memory.aux, min(first, memory.aux.len), initialized, output, 0)
  elif address >= memory.stackLow:
    let first = int(address-memory.stackLow)
    if first+length > memory.stackSize: return false
    let resident = memory.stackSize-memory.stack.len
    let zeros = min(first+length, resident)-min(first, resident)
    for index in 0..<zeros: output[index] = 0
    copyPart(memory.stack, max(first, resident)-resident, length-zeros, output, zeros)
    return true
  elif address >= memory.rwAddress:
    let first = int(address-memory.rwAddress)
    if first+length > memory.rwSize: return false
    initialized = min(first+length, memory.rw.len)-min(first, memory.rw.len)
    copyPart(memory.rw, min(first, memory.rw.len), initialized, output, 0)
    let originalFirst = min(first+initialized, memory.rwOriginal.len)
    let originalEnd = min(first+length, memory.rwOriginal.len)
    let copied = originalEnd-originalFirst
    copyPart(memory.rwOriginal, originalFirst, copied, output, initialized)
    initialized += copied
  elif address >= memory.roAddress:
    let first = int(address-memory.roAddress)
    if first+length > memory.roSize: return false
    initialized = min(first+length, memory.roData.len)-min(first, memory.roData.len)
    copyPart(memory.roData, min(first, memory.roData.len), initialized, output, 0)
  else:
    return false
  for index in initialized..<length: output[index] = 0
  true

proc writePart(buffer: var Bytes, first, length: int, input: openArray[byte], zero: bool) =
  ## Commit a host copy or zero only after its complete destination has been prepared.
  if zero: buffer.fillZero(first, length)
  else:
    assert input.len == length
    buffer.copyFrom(first, input)

proc writeOrZero(memory: var StandardMemory, address: uint32, length: int,
    input: openArray[byte], zero: bool): AccessKind =
  ## Host writes may update aux as well as RW/stack, unlike guest scalar stores.
  if address >= memory.auxAddress:
    let first = int(address-memory.auxAddress)
    let finish = first+length
    if finish > memory.aux.len:
      if finish > memory.auxSize: return AccessKind.Trap
      if not memory.resizeAux(finish): return AccessKind.MemoryLimit
    writePart(memory.aux, first, length, input, zero)
  elif address >= memory.stackLow:
    let ready = memory.prepareStack(address, length)
    if ready.kind != AccessKind.Ok: return ready.kind
    writePart(memory.stack, int(ready.value), length, input, zero)
  elif address >= memory.rwAddress:
    let first = int(address-memory.rwAddress)
    let finish = first+length
    if finish > memory.rw.len:
      if finish > memory.rwSize: return AccessKind.Trap
      if not memory.resizeRw(finish): return AccessKind.MemoryLimit
    writePart(memory.rw, first, length, input, zero)
  else:
    return AccessKind.Trap
  AccessKind.Ok

proc write*(memory: var StandardMemory, address: uint32, input: openArray[byte]): AccessKind =
  ## Public host write with exact source length; input remains caller-owned.
  writeOrZero(memory, address, input.len, input, false)

proc zero*(memory: var StandardMemory, address, length: uint32): AccessKind =
  ## Public host zero operation allocates only the source's lazily touched region.
  writeOrZero(memory, address, int(length), [], true)

proc bits[Width: static[int]](buffer: Bytes, offset: int): uint64 {.inline.} =
  ## Decode only an already proven resident span; explicit byte order supports unaligned inputs.
  assert offset >= 0 and offset <= buffer.len-Width
  let data = buffer.data
  assert data != nil
  result = 0
  for index in 0..<Width: result = result or (uint64(data[offset+index]) shl (8*index))

proc storeBits[Width: static[int]](buffer: var Bytes, offset: int, value: uint64) {.inline.} =
  ## Commit low bytes after complete checked range admission.
  assert offset >= 0 and offset <= buffer.len-Width
  let data = buffer.data
  assert data != nil
  for index in 0..<Width: data[offset+index] = byte((value shr (8*index)) and 255)

proc loadSlow[Width: static[int]](memory: StandardMemory, address: uint32): Access {.noinline.} =
  ## The source's cold load helpers materialize at most one scalar from resident/initial/zero spans.
  var bytes = default(array[Width, byte])
  if not memory.read(address, bytes): return Access(kind: AccessKind.Trap)
  var value = 0'u64
  for index in 0..<Width: value = value or (uint64(bytes[index]) shl (8*index))
  Access(kind: AccessKind.Ok, value: value)

proc load*[Width: static[int]](memory: StandardMemory, address: uint32): Access {.inline.} =
  ## Match the source's ordered resident-region fast path before its non-resident slow path.
  assert Width in [1, 2, 4, 8]
  if address >= memory.auxAddress:
    let offset = int(address-memory.auxAddress)
    if offset+Width <= memory.aux.len: return Access(kind: AccessKind.Ok, value: bits[Width](
        memory.aux, offset))
  elif address >= memory.stackResidentLow:
    let offset = int(address-memory.stackResidentLow)
    if offset+Width <= memory.stack.len: return Access(kind: AccessKind.Ok, value: bits[Width](
        memory.stack, offset))
  elif address >= memory.rwAddress:
    let offset = int(address-memory.rwAddress)
    if offset+Width <= memory.rw.len: return Access(kind: AccessKind.Ok, value: bits[Width](
        memory.rw, offset))
  elif address >= memory.roAddress:
    let offset = int(address-memory.roAddress)
    if offset+Width <= memory.roData.len: return Access(kind: AccessKind.Ok, value: readBits[Width](
        memory.roData, offset))
  loadSlow[Width](memory, address)

proc storeSlow[Width: static[int]](memory: var StandardMemory, address: uint32,
    value: uint64): Access {.noinline.} =
  ## Match the cold guest store path: aux is not writable and failed preparation commits no bytes.
  if address >= memory.stackLow:
    let ready = memory.prepareStack(address, Width)
    if ready.kind != AccessKind.Ok: return ready
    storeBits[Width](memory.stack, int(ready.value), value)
  elif address >= memory.rwAddress:
    let offset = int(address-memory.rwAddress)
    if offset+Width > memory.rwSize: return Access(kind: AccessKind.Trap)
    if not memory.resizeRw(offset+Width): return Access(kind: AccessKind.MemoryLimit)
    storeBits[Width](memory.rw, offset, value)
  else:
    return Access(kind: AccessKind.Trap)
  Access(kind: AccessKind.Ok)

proc store*[Width: static[int]](memory: var StandardMemory, address: uint32,
    value: uint64): Access {.inline.} =
  ## The hot guest store uses only resident stack/RW bytes, exactly like upstream.
  assert Width in [1, 2, 4, 8]
  if address >= memory.stackResidentLow:
    let offset = int(address-memory.stackResidentLow)
    if offset+Width <= memory.stack.len:
      storeBits[Width](memory.stack, offset, value)
      return Access(kind: AccessKind.Ok)
  elif address >= memory.rwAddress:
    let offset = int(address-memory.rwAddress)
    if offset+Width <= memory.rw.len:
      storeBits[Width](memory.rw, offset, value)
      return Access(kind: AccessKind.Ok)
  storeSlow[Width](memory, address, value)

proc growHeap*(memory: var StandardMemory, layout: MemoryLayout, size: uint32): tuple[ok: bool, top: uint32] =
  ## Translation of sbrk: grow virtual RW extent with page rounding, without eager allocation.
  let next = uint64(memory.heapSize)+uint64(size)
  if next > uint64(high(uint32)) or next > uint64(layout.maxHeapSize): return (false, 0'u32)
  memory.heapSize = uint32(next)
  let top = uint64(layout.heapBase)+next
  assert top <= uint64(high(uint32)) and layout.pageSize > 0
  if top > uint64(memory.rwAddress)+uint64(memory.rwSize):
    let rounded = ((top+uint64(layout.pageSize)-1) div uint64(layout.pageSize))*uint64(
        layout.pageSize)
    memory.rwSize = int(rounded-uint64(memory.rwAddress))
  (true, uint32(top))

func residentLengths*(memory: StandardMemory): array[3, int] =
  ## Diagnostic only, outside clocks: expose lengths without copying any guest storage.
  [memory.rw.len, memory.stack.len, memory.aux.len]
