# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Private copied read-body IR and invocation-only extent ABI for both native lowerers.

import std/assertions
import ../program
import ./[jit_rules, native_ir]

const
  NativeCheckedReadEnabled* =
    (defined(pvmX86Jit) and defined(amd64) and defined(linux)) or
    (defined(pvmArm64Jit) and not defined(pvmX86Jit) and
      defined(arm64) and (defined(linux) or defined(macosx)))
    ## Checked read admission requires a supported native lowerer.
  NativeReadSuccess* = 1'u32        ## Every staged register write committed.
  NativeReadRefusal* = high(uint32) ## No guest write occurred.
  NativeReadFactLimit* = 32'u32     ## Includes the folded leading noop and checked terminal.
  NativeReadLoadLimit = 8
  NativeReadLow = 65536'u64
  NativeReadEnd = 0xffffffff'u64    ## Exclusive conservative bound shared with checked fast loads.

type
  NativeReadBodyInfo* = object ## Geometry only. The caller must bind it to an actual checked stream.
    header*, terminal*, first*, last*: uint32
    epoch*: uint64
  NativeReadBody* = object ## The bounded copied request contains no invocation borrow.
    geometry: NativeReadBodyInfo
    operations: array[NativeReadFactLimit.int-2, NativeOperation]
    count, reads: int
  NativeReadRegion* = object ## One clipped private allocation. Empty records have no usable pointer.
    first, length: uint64
    data: nil pointer
  NativeReadContext* = array[3, NativeReadRegion] ## Current stack, writable and read-only extents.
  NativeReadWindow* = object ## One base and a compile-time hull; no invocation pointer is retained.
    base*: range[0..12]
    first*, length*: uint32

func initNativeReadBody*(header, terminal, first, last: uint32,
    epoch: uint64): NativeReadBody =
  ## One original leading noop consumes an ordinal but no physical node.
  result = default(NativeReadBody)
  if epoch == 0 or header >= terminal or terminal >= NativeEntryLimit or first >= last:
    return
  let distance = last-first
  # The header node replaces the folded noop in the geometry; the checked terminal ends both.
  if distance < 3 or distance >= NativeReadFactLimit or terminal-header != distance: return
  result.geometry = NativeReadBodyInfo(header: header, terminal: terminal, first: first,
    last: last, epoch: epoch)

func nativeReadOpcode*(opcode: byte): bool =
  ## The first shared ABI handles only relative U8, S32 and U64.
  opcode in {124'u8, 129'u8, 130'u8}

proc addReadBodyOperation*(body: var NativeReadBody, node, ordinal: uint32,
    operation: NativeOperation): bool =
  ## Reject an unsupported or discontinuous operation before updating the copied request.
  let info = body.geometry
  if info.epoch == 0 or body.count >= body.operations.len or
      body.count >= int(info.terminal-info.header-1): return false
  let next = 1'u32+uint32(body.count)
  if node != info.header+next or ordinal != info.first+next: return false
  if nativeReadOpcode(operation.opcode):
    if body.reads == NativeReadLoadLimit: return false
    inc body.reads
  elif not supportedScalarOpcode(operation.opcode): return false
  body.operations[body.count] = operation
  inc body.count
  true

func complete*(body: NativeReadBody): bool =
  ## The complete body occupies all original physical slots before the checked terminator.
  let info = body.geometry
  info.epoch != 0 and body.reads >= 2 and body.count == int(info.terminal-info.header-1)

func info*(body: NativeReadBody): NativeReadBodyInfo =
  ## Copy the certificate without exposing the request's mutable storage.
  body.geometry

func len*(body: NativeReadBody): int =
  ## Number of physical body operations, excluding the folded noop and checked terminal.
  body.count

func operation*(body: NativeReadBody, index: int): NativeOperation {.requires:
    index >= 0 and index < body.count.} =
  ## Return one copied operation within the populated extent.
  body.operations[index]

func sameReadBody*(a, b: NativeReadBody): bool =
  ## Compare the exact geometry and the admitted prefix, with no pointer identity in the request.
  if not a.complete or not b.complete or a.geometry != b.geometry or a.count != b.count:
    return false
  for index in 0..<a.count:
    let left = a.operations[index]
    let right = b.operations[index]
    if left.opcode != right.opcode or left.slots != right.slots or
        left.immediate != right.immediate: return false
  true

func nativeReadWindow*(body: NativeReadBody, maximum: uint32): NativeReadWindow =
  ## Choose the most reused base that is unchanged through the entire copied operation stream.
  ## Offsets stay unsigned so the lowerer can form the same wrapping 32-bit window start.
  result = default(NativeReadWindow)
  if not body.complete: return
  var first = default(array[13, uint32])
  var ending = default(array[13, uint64])
  var reads = default(array[13, int])
  var writes = 0'u16
  for index in 0..<body.len:
    # Every load writes A, including a load whose destination aliases its own base.
    let op = body.operation(index)
    if nativeReadOpcode(op.opcode):
      writes = writes or (1'u16 shl int(op.slots.aIndex))
      let base = op.slots.bIndex
      let opcode = int(op.opcode)
      assert opcode >= 124 and opcode <= 130
      let width = indirectMemoryAccess(range[120..130](opcode)).width
      let offset = uint32(op.immediate and 0xffffffff'u64)
      let past = uint64(offset)+uint64(width)
      if reads[base] == 0 or offset < first[base]: first[base] = offset
      if past > ending[base]: ending[base] = past
      inc reads[base]
    else:
      # A scalar destination invalidates the base even when it appears after an eligible read.
      writes = writes or (1'u16 shl int(op.slots.destinationIndex))
  var best = 1
  for slot in 0..12:
    # Count ties keep the lowest guest slot. No candidate changes the admitted certificate.
    if reads[slot] > best and (writes and (1'u16 shl slot)) == 0:
      assert ending[slot] > uint64(first[slot])
      let length = ending[slot]-uint64(first[slot])
      if length <= uint64(maximum):
        best = reads[slot]
        result = NativeReadWindow(base: range[0..12](slot), first: first[slot],
          length: uint32(length))

proc initNativeReadRegion*(first: uint64, bytes: openArray[byte]): NativeReadRegion =
  ## Borrow a readable contiguous allocation until the synchronous call returns.
  ## Its owner must keep the backing bytes in place. No ownership transfers to this view.
  result = default(NativeReadRegion)
  if first >= NativeReadEnd: return
  let low = max(first, NativeReadLow)
  let offset = low-first
  if offset >= uint64(bytes.len): return
  let length = min(uint64(bytes.len)-offset, NativeReadEnd-low)
  assert length > 0
  result = NativeReadRegion(first: low, length: length,
    data: cast[pointer](unsafeAddr bytes[int(offset)]))
