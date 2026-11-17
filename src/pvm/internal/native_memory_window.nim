# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Copied optional geometry for nearby native memory operations with one invariant source base.
## Source order and individual operands stay intact. A runtime preflight must prove one complete
## true-length region before using the hint. Failed proofs resume checked execution at the first
## original memory site, so earlier scalar effects and later partial/fault behavior stay ordered.
## These values retain no source owner, invocation pointer or entry authority. Read/write groups
## are separate; a scalar base write or a different memory base ends the current group. Literal
## and register stores can share the same proof: their original address roles, not data roles,
## determine whether the base is invariant.

import ./[jit_rules, native_ir, native_read_body]

type
  NativeWindowKind* {.pure.} = enum
    ## Reads preserve signedness per operation; writes require the current invocation's dirty pages.
    Read, Write
  NativeMemoryWindow* = object
    ## A zero count means ordinary lowering. Successful geometry covers at least two memory sites.
    first*, past*, count*: int ## Physical operation interval and number of selected memory sites.
    baseLane*: int             ## A bounded guest lane, ignored for an absolute-address group.
    displacement*, span*, members*: uint32 ## Wrapped minimum, true byte extent and physical-site bits.
    kind*: NativeWindowKind
    absolute*: bool            ## Absolute groups consume no live guest address register.

func nativeWindowOpcode*(opcode: byte): byte {.inline.} =
  ## Normalize absolute/relative register and literal memory families, or return zero.
  case opcode
  of 30..33: opcode+90'u8
  of 52..58: opcode+72'u8
  of 59..62: opcode+61'u8
  of 70..73: opcode+50'u8
  of 120..130: opcode
  else: 0'u8

func nativeWindowAbsolute(opcode: byte): bool {.inline.} =
  ## Absolute literal and register transfers have no live guest address base.
  opcode in {30'u8..33, 52..62}

func nativeWindowBase(operation: NativeOperation): int {.inline.} =
  ## Relative literal stores consume original A; relative register transfers consume original B.
  if operation.opcode in {70'u8..73}: int(operation.slots.aIndex)
  else: int(operation.slots.bIndex)

func ready*(window: NativeMemoryWindow): bool {.inline.} =
  ## Only a complete multi-site hint can replace ordinary guards.
  window.count >= 2

func contains*(window: NativeMemoryWindow, index: int): bool {.inline.} =
  ## Empty or out-of-range coordinates select no operation before any bit shift.
  if index < 0 or index >= int(NativeReadFactLimit)-1: return false
  window.ready and (window.members and (1'u32 shl index)) != 0

func nativeMemoryWindow*(operations: array[int(NativeReadFactLimit)-1, NativeOperation],
    count, first: int): NativeMemoryWindow =
  ## Find one bounded same-kind group from the supplied physical site. The completed source body
  ## owns every operand; this call borrows it without copying or retaining its storage. Signed
  ## widened displacement arithmetic proves extent/alignment before narrowing. A base-writing
  ## load can end a group, because every earlier address still consumed the original base.
  result = default(NativeMemoryWindow)
  if count < 0 or count > operations.len or first < 0 or first >= count: return
  let initial = operations[first]
  let encoding = nativeWindowOpcode(initial.opcode)
  if encoding < 120 or encoding > 130: return
  let absolute = nativeWindowAbsolute(initial.opcode)
  let kind = if encoding <= 123: NativeWindowKind.Write else: NativeWindowKind.Read
  let base = if absolute: 0 else: nativeWindowBase(initial)
  var minimum = high(int64)
  var maximum = low(int64)
  var members = 0'u32
  var taken = 0
  var past = first
  for index in first..<count:
    # Infallible scalar work may remain between selected accesses while preserving their base.
    let op = operations[index]
    let code = nativeWindowOpcode(op.opcode)
    if code < 120 or code > 130:
      if not supportedScalarOpcode(op.opcode) or
          (not absolute and int(op.slots.destinationIndex) == base): break
      continue
    let access = indirectMemoryAccess(range[120..130](code))
    let nextKind = if code <= 123: NativeWindowKind.Write else: NativeWindowKind.Read
    if nativeWindowAbsolute(op.opcode) != absolute or nextKind != kind or
        (not absolute and nativeWindowBase(op) != base): break
    let displacement = int64(cast[int32](uint32(op.immediate and 0xffffffff'u64)))
    let low = min(minimum, displacement)
    let high = max(maximum, displacement+int64(access.width))
    if high-low > 4096: break
    minimum = low
    maximum = high
    members = members or (1'u32 shl index)
    inc taken
    past = index+1
    if not absolute and kind == NativeWindowKind.Read and int(op.slots.aIndex) == base:
      # A final load may replace the old base only after its own address has been formed.
      break
  if taken < 2: return
  for index in first..<past:
    # Every retained offset must fit ARM's scaled immediate, even for mixed access widths.
    if (members and (1'u32 shl index)) == 0: continue
    let op = operations[index]
    let code = nativeWindowOpcode(op.opcode)
    if code < 120 or code > 130: return
    let width = indirectMemoryAccess(range[120..130](code)).width
    let displacement = int64(cast[int32](uint32(op.immediate and 0xffffffff'u64)))
    if (displacement-minimum) mod int64(width) != 0: return
  result = NativeMemoryWindow(first: first, past: past, count: taken,
    baseLane: (if absolute: 0 else: base), displacement: cast[uint32](int32(minimum)),
    span: uint32(maximum-minimum), members: members, kind: kind, absolute: absolute)
