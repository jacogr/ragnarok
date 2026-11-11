# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Mixed loop source admission with relocated operands, folded facts and shape refusals.

import std/assertions
import ../../src/codec/natural
import ../../src/pvm/program
import ../../src/pvm/internal/[handler_stream, native_mixed_loop, native_read_cycle]

type PatternVariant {.pure.} = enum
  Exact, Alias, WrongStore, FoldedNoop, WrongTarget, ReadAfterStore, OverBound

proc appendNatural(wire: var seq[byte], value: uint64) =
  ## Emit the bounded encoded length from the public codec.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len: wire.add(encoded.bytes[index])

proc pattern(pc: uint32, variant: PatternVariant, prefixMisses: int = 0): Program =
  ## Construct genuine branch targets and explicit instruction-start bits.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  template emit(op: openArray[byte]) =
    starts.add(code.len)
    for item in op: code.add(item)
  for _ in 0..<int(pc): emit([0'u8])
  for index in 0..prefixMisses:
    # Near misses fall through into the next complete original loop.
    let form = if index < prefixMisses: PatternVariant.WrongStore else: variant
    let loopPc = code.len
    emit([152'u8, 0x88, 1])
    emit([210'u8, 0x88, 9])
    emit([58'u8, 8, 0, 0, 1, 0])
    emit([139'u8, 0x88, 0])
    emit([212'u8, 0x88, 9])
    emit([58'u8, 9, 8, 0, 1, 0])
    emit([200'u8, 0x88, 9])
    emit([124'u8, 0x6a, 0])
    emit([200'u8, 0x99, 10])
    emit([124'u8, 0x6b, 1])
    if form == PatternVariant.FoldedNoop: emit([2'u8])
    if prefixMisses > 0: emit([149'u8, 0xb2, 1])
    else: emit([149'u8, 0x22, 1])
    if form == PatternVariant.WrongStore: emit([121'u8, 0x50, 0])
    elif form == PatternVariant.Alias: emit([120'u8, 0x52, 1])
    else: emit([120'u8, 0x50, 0])
    if form == PatternVariant.ReadAfterStore: emit([124'u8, 0x6a, 0])
    if form == PatternVariant.OverBound:
      for _ in 0..<18: emit([2'u8])
    emit([190'u8, 0x75, 5])
    emit([100'u8, 0x43])
    let target = if form == PatternVariant.WrongTarget: 0 else: loopPc
    let displacement = cast[uint32](int32(target-code.len))
    emit([171'u8, 0xc2, byte(displacement and 255),
      byte((displacement shr 8) and 255), byte((displacement shr 16) and 255),
      byte(displacement shr 24)])
  emit([0'u8])
  var wire = @[0'u8, 0]
  appendNatural(wire, uint64(code.len))
  for item in code: wire.add(item)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for item in mask: wire.add(item)
  let decoded = decodeProgram(wire, CodeAddress(uint64(pc)), ProgramByteLimit(1024),
    JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  decoded.value

proc runMixedLoopSource*() =
  ## Validate the two-borrow layout and compare original source authority with the linked stream.
  assert sizeof(NativeMixedLoopContext) == NativeMixedLoopContextBytes
  var context = default(NativeMixedLoopContext)
  let contextBase = cast[uint](addr context)
  assert cast[uint](addr context.read)-contextBase == 0'u
  assert cast[uint](addr context.writable)-contextBase == uint(NativeCycleWritableOffset)
  assert cast[uint](addr context.dirty)-contextBase == uint(NativeCycleDirtyOffset)
  assert cast[uint](addr context.dirtyWords)-contextBase == uint(NativeCycleDirtyWordsOffset)
  assert cast[uint](addr context.visitLimit)-contextBase == uint(NativeMixedLoopVisitLimitOffset)
  witnessFlatMixedLoop(pattern(0, PatternVariant.Exact), 0, true)
  witnessFlatMixedLoop(pattern(83, PatternVariant.Alias), 83, true)
  witnessFlatMixedLoop(pattern(37, PatternVariant.WrongStore), 37, false)
  witnessFlatMixedLoop(pattern(37, PatternVariant.FoldedNoop), 37, true)
  witnessFlatMixedLoop(pattern(37, PatternVariant.WrongTarget), 37, false)
  witnessFlatMixedLoop(pattern(37, PatternVariant.ReadAfterStore), 37, false)
  witnessFlatMixedLoop(pattern(37, PatternVariant.OverBound), 37, false)
  when defined(pvmMixedLoopEntryWitness):
    witnessFlatMixedLoopEntry(pattern(0, PatternVariant.Exact), 0)
