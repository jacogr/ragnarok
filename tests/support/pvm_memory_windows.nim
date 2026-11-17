# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise grouped native memory against independent scalar byte and complete-ledger oracles.
## Literal guest instructions own operand coordinates; hostile views test conservative paid replay.

import std/assertions
import ../../src/codec/natural
import ../../src/pvm/[program, machine]
import ../../src/pvm/internal/[native_ir, native_platform, native_fusion, native_read_body,
  native_read_cycle, native_memory_window]

when NativeReadCycleEnabled:
  proc windowLiteral(bytes: openArray[byte]): NativeOperation =
    ## Decode one genuine marked instruction, keeping the test independent of emitter operands.
    var wire = @[0'u8, 0]
    let length = encode(JamNatural(uint64(bytes.len+1)))
    for index in 0..<length.len: wire.add(length.bytes[index])
    for value in bytes: wire.add(value)
    wire.add(0)
    var mask = newSeq[byte]((bytes.len+8) div 8)
    mask[0] = 1
    mask[bytes.len div 8] = mask[bytes.len div 8] or (1'u8 shl (bytes.len mod 8))
    for value in mask: wire.add(value)
    let owner = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(32), JumpCountLimit(0))
    assert owner.error == ProgramError.None
    let decoded = instruction(owner.value, CodeAddress(0))
    assert decoded.error == ProgramError.None
    let immediate = if decoded.value.opcode in {30'u8..33, 70..73}:
        (uint64(decoded.value.x) and 0xffffffff'u64) or
          ((uint64(decoded.value.y) and 0xffffffff'u64) shl 32)
      else: uint64(decoded.value.x)
    NativeOperation(opcode: decoded.value.opcode, slots: instructionRegisters(decoded),
      immediate: immediate)

  proc windowTransfer(opcode: byte, absolute: bool, value: byte,
      displacement: uint32): NativeOperation =
    ## Absolute and relative forms use distinct literal wire opcodes with one fixed immediate width.
    let wireOpcode = if absolute:
      (if opcode <= 123: opcode-61'u8 else: opcode-72'u8) else: opcode
    var bytes = @[wireOpcode, (if absolute: value else: 0x60'u8 or value)]
    for index in 0..<4: bytes.add(byte((displacement shr (index*8)) and 255))
    windowLiteral(bytes)

  proc checkWindowGeometry() =
    ## Base mutations, mixed kinds, unsupported gaps and unaligned scaled offsets stay ordinary.
    var operations = default(array[int(NativeReadFactLimit)-1, NativeOperation])
    operations[0] = windowTransfer(127, false, 7, 0)
    operations[1] = windowLiteral([149'u8, 0x66, 1])
    operations[2] = windowTransfer(127, false, 8, 4)
    assert not nativeMemoryWindow(operations, 3, 0).ready
    operations[1] = windowLiteral([215'u8, 0xa9, 11])
    operations[2] = windowTransfer(127, false, 6, 4)
    assert nativeMemoryWindow(operations, 3, 0).ready, "a final base-writing load uses its old base"
    operations[0] = windowTransfer(127, false, 6, 0)
    assert not nativeMemoryWindow(operations, 3, 0).ready
    operations[0] = windowTransfer(124, false, 7, 0)
    operations[2] = windowTransfer(130, false, 8, 1)
    assert not nativeMemoryWindow(operations, 3, 0).ready
    operations[2] = windowTransfer(120, false, 8, 1)
    assert not nativeMemoryWindow(operations, 3, 0).ready
    operations[2] = windowTransfer(124, false, 8, 4096)
    assert not nativeMemoryWindow(operations, 3, 0).ready
    assert not nativeMemoryWindow(operations, -1, 0).ready
    assert not nativeMemoryWindow(operations, operations.len+1, 0).ready
    assert not nativeMemoryWindow(operations, 3, -1).ready
    assert not default(NativeMemoryWindow).contains(-1)
    assert not default(NativeMemoryWindow).contains(32)

  proc windowLiteralStore(opcode: byte, absolute: bool, base: byte,
      displacement, literal: uint32): NativeOperation =
    ## Independent wire bytes distinguish literal A bases from register-store B bases.
    let wireOpcode = opcode-(if absolute: 90'u8 else: 50'u8)
    var bytes = @[wireOpcode, (if absolute: 4'u8 else: 0x40'u8 or base)]
    for index in 0..<4: bytes.add(byte((displacement shr (index*8)) and 255))
    for index in 0..<4: bytes.add(byte((literal shr (index*8)) and 255))
    windowLiteral(bytes)

  proc checkLiteralWindowGeometry() =
    ## Data lanes never stand in for address bases; a live base write ends a mixed store group.
    var operations = default(array[int(NativeReadFactLimit)-1, NativeOperation])
    operations[0] = windowLiteralStore(120, false, 6, 0, 0)
    operations[1] = windowLiteral([149'u8, 0x77, 1])
    operations[2] = windowTransfer(123, false, 8, 8)
    let mixed = nativeMemoryWindow(operations, 3, 0)
    assert mixed.ready and mixed.baseLane == 6 and not mixed.absolute and mixed.span == 16
    operations[2] = windowLiteralStore(123, false, 6, 8, 0xffffffff'u32)
    assert nativeMemoryWindow(operations, 3, 0).ready
    operations[2] = windowLiteralStore(123, false, 7, 8, 0xffffffff'u32)
    assert not nativeMemoryWindow(operations, 3, 0).ready
    operations[2] = windowLiteralStore(123, false, 6, 8, 0)
    operations[1] = windowLiteral([149'u8, 0x66, 1])
    assert not nativeMemoryWindow(operations, 3, 0).ready
    operations[0] = windowLiteralStore(120, true, 0, 65536, 0)
    operations[2] = windowLiteralStore(123, true, 0, 65544, 0)
    let absolute = nativeMemoryWindow(operations, 3, 0)
    assert absolute.ready and absolute.absolute and absolute.span == 16

  proc checkWindowTransfers(opcode: byte, absolute: bool, scenario: int,
      literalPosition: int = -1, literal: uint32 = 0) =
    ## Preserve complete registers, bytes, dirty authority and receipts on success or first-site replay.
    let writing = opcode <= 123
    let width = case opcode
      of 120, 124, 125: 1
      of 121, 126, 127: 2
      of 122, 128, 129: 4
      else: 8
    let signed = opcode in [125'u8, 127, 129]
    let crossing = scenario in [8, 9, 10, 11]
    let address = if scenario == 15: 65535'u64
      elif scenario == 16: 0xfffffff8'u64
      elif crossing: 0x3fffc'u64 else: 0x10001'u64
    let displacement = if scenario == 12 and not absolute: 0xfffffff8'u32 else: 0'u32
    let first = if absolute: uint32(address) else: displacement
    var blocks = [
      NativeFusionBlock(header: 10, terminal: 14, span: 4, price: 11, guards: 5,
        targets: [20'u32, NativeEntryFailure], branch: NativeOperation(opcode: 40)),
      NativeFusionBlock(header: 20, terminal: 22, first: 4, span: 2, price: 7,
        targets: [100'u32, NativeEntryFailure], branch: NativeOperation(opcode: 40))]
    blocks[0].operations[0] = windowTransfer(opcode, absolute, 7, first)
    blocks[0].operations[1] = windowLiteral([215'u8, 0xa9,
      (if scenario == 18 and writing: 8'u8 else: 11'u8)])
    blocks[0].operations[2] = windowTransfer(opcode, absolute,
      (if scenario == 13 and not absolute and not writing: 6'u8 else: 8'u8), first+8)
    if literalPosition >= 0:
      # Position two selects both sites; mixed pairs independently exercise both original base roles.
      assert writing and literalPosition <= 2
      for member in 0..1:
        if member == literalPosition or literalPosition == 2:
          blocks[0].operations[member*2] = windowLiteralStore(opcode, absolute, 6,
            first+uint32(member*8), literal xor uint32(member*0x100))
    blocks[1].operations[0] = windowLiteral([149'u8, 0xcc, 1])
    let window = nativeMemoryWindow(blocks[0].operations, 3, 0)
    assert window.ready and window.count == 2 and window.span == uint32(8+width)
    let image = lowerNativeFusion(blocks)
    assert image.ready and nativeFusionEntry(image, 0)
    var storage = default(array[26, byte])
    for index in 0..<storage.len: storage[index] = byte(0x80+index)
    var expectedStorage = storage
    var registers = default(RegisterFile)
    for lane in 0..12:
      registers[lane] = RegisterValue(0xfedcba9800000000'u64+uint64(lane)*0x01020304'u64)
    registers[6] = RegisterValue(0x1234567800000000'u64 or
      uint64(uint32(address)-displacement))
    registers[9] = RegisterValue(0)
    let initial = registers
    var expected = initial
    var dirty = [high(uint64), high(uint64)]
    if scenario == 7: dirty[int(address shr 18)] = 0
    if scenario == 9: dirty[1] = dirty[1] and not 1'u64
    if scenario == 11: dirty[0] = dirty[0] and not (1'u64 shl 63)
    let dirtyBefore = dirty
    var state = NativeFusionContext(gas: 100, remaining: 100)
    if writing:
      # The live borrow is intentionally unaligned and a true length, not a legacy clipped bound.
      state.memory.writable[1] = NativeCycleWritable(first: address, length: 24,
        data: addr storage[1])
      state.memory.dirty = addr dirty[0]
      state.memory.dirtyWords = (if scenario == 10: 1'u64 else: 2'u64)
      if scenario in [1, 4]: state.memory.writable[1].length = uint64(width)
      if scenario == 2:
        state.memory.writable[0] = NativeCycleWritable(first: address+8,
          length: uint64(width), data: addr storage[9])
      if scenario == 3:
        state.memory.writable[0] = NativeCycleWritable(first: address-1,
          length: 1, data: addr storage[0])
      if scenario == 5: state.memory.writable[1].data = nil
      if scenario == 6:
        state.memory.writable[0] = state.memory.writable[1]
        state.memory.writable[1].length = uint64(width)
      if scenario == 17:
        state.memory.writable[0] = NativeCycleWritable(first: address,
          length: 8, data: addr storage[1])
        state.memory.writable[1] = NativeCycleWritable(first: address+8,
          length: 16, data: addr storage[9])
      if scenario == 14:
        state.memory.writable = default(array[2, NativeCycleWritable])
        state.memory.read[2] = initNativeReadRegion(address, storage.toOpenArray(1, 24))
    else:
      state.memory.read[1] = initNativeReadRegion(address, storage.toOpenArray(1, 24))
      if scenario in [1, 4]:
        state.memory.read[1] = initNativeReadRegion(address, storage.toOpenArray(1, width))
      if scenario == 2:
        state.memory.read[0] = initNativeReadRegion(address+8, storage.toOpenArray(9, 8+width))
      if scenario == 3:
        state.memory.read[0] = initNativeReadRegion(address-1, storage.toOpenArray(0, 0))
      if scenario == 6:
        state.memory.read[0] = state.memory.read[1]
        state.memory.read[1] = initNativeReadRegion(address, storage.toOpenArray(1, width))
      if scenario == 17:
        state.memory.read[0] = initNativeReadRegion(address, storage.toOpenArray(1, 8))
        state.memory.read[1] = initNativeReadRegion(address+8, storage.toOpenArray(9, 24))
      if scenario == 14:
        state.memory.read[2] = state.memory.read[1]
        state.memory.read[1] = default(NativeReadRegion)
    let success = scenario notin [1, 2, 4, 15, 16, 17] and
      (not writing or scenario notin [5, 7, 9, 10, 11, 14])
    if success:
      # Construct the scalar transfer oracle from bytes, independently of instruction encoders.
      if scenario == 18 and writing: expected[8] = RegisterValue(0)
      else: expected[11] = RegisterValue(0)
      expected[12] = RegisterValue(uint64(initial[12])+1)
      for member in 0..1:
        let lane = if member == 0: 7 else:
          (if scenario == 13 and not absolute and not writing: 6 else: 8)
        let offset = 1+member*8
        if writing:
          let value = if member == literalPosition or literalPosition == 2:
              let bits = literal xor uint32(member*0x100)
              if bits >= 0x80000000'u32: uint64(bits) or 0xffffffff00000000'u64
              else: uint64(bits)
            else: uint64(expected[lane])
          for index in 0..<width:
            expectedStorage[offset+index] = byte((value shr (index*8)) and 255)
        else:
          var value = 0'u64
          for index in 0..<width: value = value or (uint64(storage[offset+index]) shl (index*8))
          if signed and (storage[offset+width-1] and 128) != 0:
            value = value or (high(uint64) shl (width*8))
          expected[lane] = RegisterValue(value)
    let next = enterNativeFusion(image, 0, registers, state)
    assert next == (if success: 100'u32 else: 11'u32),
      "window exit opcode=" & $opcode & " absolute=" & $absolute & " scenario=" & $scenario
    assert registers == expected and storage == expectedStorage and dirty == dirtyBefore,
      "window complete state opcode=" & $opcode & " scenario=" & $scenario
    assert state.visits == (if success: 2'u64 else: 1'u64)
    assert state.paid == (if success: 0'u64 else: 1'u64)
    assert state.gas == (if success: 82'u64 else: 89'u64)
    assert state.remaining == (if success: 94'u64 else: 96'u64)
    let receipt = nativeFusionExit(blocks, 10, next, 100, 100, state)
    assert receipt.valid and receipt.attempted == (if success: 6'u32 else: 4'u32)

proc runMemoryWindows*() =
  ## The shared native suite runs every memory width and addressing form on each supported ISA.
  when NativeReadCycleEnabled:
    checkWindowGeometry()
    checkLiteralWindowGeometry()
    for opcode in 120'u8..130'u8:
      for absolute in [false, true]:
        for scenario in 0..18: checkWindowTransfers(opcode, absolute, scenario)
    for opcode in 120'u8..123'u8:
      for absolute in [false, true]:
        for position in 0..2:
          for literal in [0'u32, 0x100'u32, 0x10000'u32, 0x80000000'u32, 0xffffffff'u32]:
            for scenario in 0..18:
              # Reuse the independent complete-state/dirty/receipt oracle for literal and mixed windows.
              checkWindowTransfers(opcode, absolute, scenario, position, literal)
