# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private native publication, indexed dispatch, code-cap and move-lifetime witnesses.

import std/[assertions, syncio]
import ../../src/pvm/[machine, program]
import ../../src/pvm/internal/[native_ir, native_mixed_loop, native_platform, native_read_body,
  native_read_cycle]
when defined(pvmX86Jit):
  import ../../src/pvm/internal/x86_jit
else:
  import ../../src/pvm/internal/arm64_jit

const
  base = 65536'u64
  wordAddress = base+16
  pvmMixedLoopPublishFail {.intdefine.} = -1

proc operation(opcode, lanes: byte, operand: uint32 = 0): NativeOperation =
  ## Bind register roles through the real decoder before constructing copied test IR.
  let wire = [0'u8, 0, 7, opcode, lanes, byte(operand and 255), byte((operand shr 8) and 255),
    byte((operand shr 16) and 255), byte(operand shr 24), 0, 0x41]
  let owner = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert owner.error == ProgramError.None
  let decoded = instruction(owner.value, CodeAddress(0))
  assert decoded.error == ProgramError.None
  NativeOperation(opcode: opcode, slots: instructionRegisters(decoded),
    immediate: uint64(decoded.value.x))

proc byteProof(slot: int, reads = 1): NativeMixedLoop =
  ## Each proof has independent original source and stream coordinates under one epoch.
  let header = uint32(100+slot*100)
  let count = uint8(reads+3)
  result = NativeMixedLoop(header: header, first: header, terminal: header+uint32(count),
    exitHeader: header+uint32(count)+1, price: 10, epoch: 1, span: count, count: count)
  for index in 0..<reads:
    # Repeated real Reads expand the leaf without changing its final expected state.
    result.operations[index] = operation(124, 0x61)
  result.operations[reads] = operation(120, 0x50)
  result.operations[reads+1] = operation(149, 0x55, 1)
  result.operations[reads+2] = operation(171, 0xc5)
  assert result.complete

proc paidProof(slot: int): NativeMixedLoop =
  ## A byte Store precedes a live signed Load and a separate absolute word Store.
  let header = uint32(100+slot*100)
  result = NativeMixedLoop(header: header, first: header, terminal: header+6,
    exitHeader: header+7, price: 10, epoch: 1, span: 6, count: 6)
  let operations = [operation(124, 0x61), operation(120, 0x50),
    operation(57, 3, uint32(base)), operation(61, 3, uint32(wordAddress)),
    operation(149, 0x55, 1), operation(171, 0xc5)]
  for index, item in operations: result.operations[index] = item
  result.paidGuards = nativeMixedLoopPaidGuards(result)
  assert result.paidGuards == 15 and result.complete

proc encoded(proof: NativeMixedLoop): seq[byte] =
  ## Independently retain the pure emitter bytes for comparison with the actual RX mapping.
  template operations: untyped = proof.operations.toOpenArray(0, int(proof.count)-1)
  when defined(pvmX86Jit):
    result = if proof.paidGuards != 0:
        x86PaidMixedLoopInstructions(operations, proof.paidGuards)
      else: x86MixedLoopInstructions(operations)
  else:
    let words = if proof.paidGuards != 0:
        armPaidMixedLoopInstructions(operations, proof.paidGuards)
      else: armMixedLoopInstructions(operations)
    result = @[]
    for word in words:
      # ARM instruction bytes are explicitly little-endian in the maintained arena ABI.
      for shift in 0..<4: result.add(byte((word shr (shift*8)) and 255))

proc checkEntry(image: NativeImage, slot: uint8, paid: bool) =
  ## Enter the chosen published leaf with fresh capabilities and compare every visible write.
  var bytes = default(array[32, byte])
  bytes[0] = 0x17
  bytes[1] = 0x22
  bytes[2] = 0x33
  bytes[3] = 0x80
  let original = bytes
  var dirty = 1'u64 shl (base shr 12)
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xa5)
  registers[5] = RegisterValue(base)
  registers[6] = RegisterValue(base)
  registers[12] = RegisterValue(base+1)
  let incoming = registers
  var context = NativeMixedLoopContext(visitLimit: 1)
  context.read[1] = initNativeReadRegion(base, bytes)
  context.writable[0].first = uint64(high(uint32))+1
  context.writable[1] = NativeCycleWritable(first: base, length: uint64(bytes.len),
    data: addr bytes[0])
  context.dirty = addr dirty
  context.dirtyWords = 1
  let receipt = enterNativeMixedLoopAt(image, slot, registers, context)
  assert receipt == (NativeMixedLoopExitBit or 1'u32)
  for index in 0..12:
    let expected = case index
      of 1: RegisterValue(0x17)
      of 3: (if paid: RegisterValue(0xffffffff803322a5'u64) else: incoming[index])
      of 5: RegisterValue(base+1)
      else: incoming[index]
    assert registers[index] == expected
  for index in 0..<bytes.len:
    let expected = if index == 0: 0xa5'u8
      elif paid and index in 16..19:
        byte((0x803322a5'u32 shr ((index-16)*8)) and 255)
      else: original[index]
    assert bytes[index] == expected
  assert dirty == (1'u64 shl (base shr 12)) and context.visitLimit == 1

  # The same indexed ABI must select distinct transactional and paid refusal receipts.
  registers = incoming
  var empty = NativeMixedLoopContext(visitLimit: 1)
  let refused = enterNativeMixedLoopAt(image, slot, registers, empty)
  assert refused == (if paid: 1'u32 shl NativeMixedLoopGuardShift else: 0'u32)
  assert registers == incoming

proc pairProof(): NativeMixedLoopSet =
  ## The normal ranked pair covers both memory publication contracts.
  result = singleNativeMixedLoop(byteProof(0))
  result.count = 2
  result.proofs[1] = paidProof(1)
  assert result.complete

block native_image_publication:
  # The private controller builds each fault slot separately against the real publisher.
  assert nativePlatformSupported()
  let candidates = pairProof()
  var refused = 0'u8
  var pairRefused = false
  var image = lowerNativeMixedLoops(candidates, refused, pairRefused)
  assert refused == 0 and not pairRefused
  when pvmMixedLoopPublishFail >= 0:
    assert not image.ready and nativeMixedLoopEntries(image) == 0 and image.codeBytes == 0
    # Native qualification also requires the publisher's observed failure and cleanup receipt.
  else:
    assert image.ready and nativeMixedLoopEntries(image) == 3
    let first = witnessNativeMixedLoopImage(image, 0, encoded(candidates.proofs[0]))
    let second = witnessNativeMixedLoopImage(image, 1, encoded(candidates.proofs[1]))
    const alignment = when defined(pvmX86Jit): 16'u32 else: 4'u32
    assert first.offset == 0
    assert second.offset == ((first.length+alignment-1) and not (alignment-1))
    assert uint64(second.offset)+uint64(second.length) == image.codeBytes
    checkEntry(image, 0, false)
    checkEntry(image, 1, true)
    var moved = move(image)
    assert not image.ready and nativeMixedLoopEntries(image) == 0 and image.codeBytes == 0
    checkEntry(moved, 1, true)
    echo "MIXED_ARENA_IMAGES,", first.offset, ",", first.length, ",", second.offset, ",",
      second.length, ",", moved.codeBytes

when pvmMixedLoopPublishFail < 0:
  block reversed_entry_order:
    # Paid-first ordering exercises x86 padding before the second exact leaf.
    var candidates = singleNativeMixedLoop(paidProof(0))
    candidates.count = 2
    candidates.proofs[1] = byteProof(1)
    var refused = 0'u8
    var pairRefused = false
    var image = lowerNativeMixedLoops(candidates, refused, pairRefused)
    assert image.ready and nativeMixedLoopEntries(image) == 3
    assert refused == 0 and not pairRefused
    let first = witnessNativeMixedLoopImage(image, 0, encoded(candidates.proofs[0]))
    let second = witnessNativeMixedLoopImage(image, 1, encoded(candidates.proofs[1]))
    const alignment = when defined(pvmX86Jit): 16'u32 else: 4'u32
    assert first.offset == 0 and second.offset ==
      ((first.length+alignment-1) and not (alignment-1))
    assert image.codeBytes == uint64(second.offset)+uint64(second.length)
    checkEntry(image, 0, true)
    checkEntry(image, 1, false)
    echo "MIXED_ARENA_REVERSED,", second.offset, ",", image.codeBytes

  block rejected_set_authority:
    # A stale epoch or overlapping source pair cannot acquire callable offsets.
    var candidates = pairProof()
    candidates.proofs[1].epoch = 2
    var refused = 0'u8
    var pairRefused = false
    var image = lowerNativeMixedLoops(candidates, refused, pairRefused)
    assert not image.ready and refused == 3 and not pairRefused
    candidates = pairProof()
    candidates.proofs[1].first = candidates.proofs[0].first
    image = lowerNativeMixedLoops(candidates, refused, pairRefused)
    assert not image.ready and refused == 3 and not pairRefused
    assert nativeMixedLoopEntries(image) == 0
    echo "MIXED_ARENA_AUTHORITY_OK"

  block code_cap_fallback:
    # Both leaves fit individually. Their combined bytes exceed the one-image cap.
    var candidates = singleNativeMixedLoop(byteProof(0, 18))
    candidates.count = 2
    candidates.proofs[1] = byteProof(1, 18)
    let bytes = encoded(candidates.proofs[0])
    assert bytes.len > NativeImageByteLimit div 2 and bytes.len <= NativeImageByteLimit
    var refused = 0'u8
    var pairRefused = false
    var image = lowerNativeMixedLoops(candidates, refused, pairRefused)
    assert image.ready and nativeMixedLoopEntries(image) == 1
    assert refused == 0 and pairRefused
    discard witnessNativeMixedLoopImage(image, 0, bytes)
    assert image.codeBytes == uint64(bytes.len)
    checkEntry(image, 0, false)
    echo "MIXED_ARENA_CAP,", image.codeBytes

  block later_slot_after_aggregate_refusals:
    # A smaller final leaf still fits after intermediate ranked leaves exceeded the cap.
    var candidates = default(NativeMixedLoopSet)
    candidates.count = uint8(NativeMixedLoopEntryLimit)
    for index in 0..<NativeMixedLoopEntryLimit:
      candidates.proofs[index] = byteProof(index, if index ==
          NativeMixedLoopEntryLimit-1: 1 else: 18)
    var refused = 0'u8
    var pairRefused = false
    var image = lowerNativeMixedLoops(candidates, refused, pairRefused)
    assert image.ready and nativeMixedLoopEntries(image) == 129
    assert refused == 0 and pairRefused
    discard witnessNativeMixedLoopImage(image, 0, encoded(candidates.proofs[0]))
    discard witnessNativeMixedLoopImage(image, 7, encoded(candidates.proofs[7]))
    checkEntry(image, 0, false)
    checkEntry(image, 7, false)
    echo "MIXED_ARENA_LAST_SLOT,", nativeMixedLoopEntries(image), ",", refused

  when defined(pvmX86Jit):
    block later_slot_after_individual_refusals:
      # The larger x86 read guards make the maximum valid source exceed the per-leaf cap.
      var candidates = default(NativeMixedLoopSet)
      candidates.count = uint8(NativeMixedLoopEntryLimit)
      for index in 0..<NativeMixedLoopEntryLimit:
        candidates.proofs[index] = byteProof(index, if index ==
            NativeMixedLoopEntryLimit-1: 1 else: 29)
      assert encoded(candidates.proofs[0]).len == 0
      var refused = 0'u8
      var pairRefused = false
      var image = lowerNativeMixedLoops(candidates, refused, pairRefused)
      assert image.ready and nativeMixedLoopEntries(image) == 128
      assert refused == 127 and not pairRefused
      discard witnessNativeMixedLoopImage(image, 7, encoded(candidates.proofs[7]))
      checkEntry(image, 7, false)
      echo "MIXED_ARENA_INDIVIDUAL_REFUSAL,", nativeMixedLoopEntries(image), ",", refused

  block single_leaf_compatibility:
    # Existing callers retain the same proof and two-borrow entry wrapper.
    let proof = byteProof(0)
    var refused = false
    var image = lowerNativeMixedLoop(proof, refused)
    assert image.ready and not refused and nativeMixedLoopEntries(image) == 1
    checkEntry(image, 0, false)
    let invalid = default(NativeMixedLoop)
    image = lowerNativeMixedLoop(invalid, refused)
    assert not image.ready and refused
    assert nativeMixedLoopEntries(image) == 0
    echo "MIXED_ARENA_SINGLE_OK"

echo "MIXED_ARENA_OK"
