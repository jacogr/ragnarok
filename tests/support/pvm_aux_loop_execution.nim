# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Construct independent auxiliary source and refusal fixtures for each native lowerer.

import std/[assertions, syncio]
import ../../src/codec/natural
import ../../src/pvm/program
import ../../src/pvm/internal/handler_stream
import ./pvm_read_cycle_execution

type PatternVariant {.pure.} = enum
  Exact, Alias, WrongStore, FoldedNoop, WrongTarget

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

proc refusalProgram(): Program =
  ## Assemble a bounded body with late reads and stores that vary across visits.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  template append(op: openArray[byte]) =
    starts.add(code.len)
    for b in op: code.add(b)

  append([58'u8, 0, 0, 0, 1, 0])
  append([124'u8, 0x61, 0])
  append([149'u8, 0x66, 1])
  for _ in 0..<8: append([149'u8, 0x22, 1])
  append([120'u8, 0x50, 0])
  append([190'u8, 0x75, 5])
  append([100'u8, 0x43])
  let back = 256-code.len
  append([171'u8, 0xc2, byte(back), 0xff, 0xff, 0xff])
  append([0'u8])
  var wire = @[0'u8, 0, byte(code.len)]
  for b in code: wire.add(b)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for b in mask: wire.add(b)
  let source = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(256), JumpCountLimit(0))
  assert source.error == ProgramError.None
  source.value

proc runAuxLoopExecution*() =
  ## Compare native and checked frames and exercise real compiler pressure.
  witnessAuxSourcePattern(pattern(0, PatternVariant.Exact), 0, 1, true, false)
  witnessAuxSourcePattern(pattern(83, PatternVariant.Alias), 83, 1, true, true)
  witnessAuxSourcePattern(pattern(37, PatternVariant.WrongStore), 37, 1, false, false)
  witnessAuxSourcePattern(pattern(37, PatternVariant.FoldedNoop), 37, 0, false, false)
  witnessAuxSourcePattern(pattern(37, PatternVariant.WrongTarget), 37, 0, false, false)
  witnessAuxSourcePattern(pattern(37, PatternVariant.Exact, prefixMisses = 8),
    37, 8, false, false, oneVisit = true)
  witnessAuxRefusals(refusalProgram())
  runAuxiliaryMailbox()
  echo "PASS auxiliary loop source, refusal and mailbox"
