# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Local JIT alias/overflow and reservation witness against the engine's bounded single-step adapter.
import std/[assertions, syncio]
import ../../src/codec/natural
import ../../src/pvm/[program, machine, gas, step, registers, gas_plan, gas_memo]
when defined(pvmArm64Jit):
  import ../../src/pvm/internal/arm64_jit
import ../../src/pvm/internal/handler_stream
proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Test framing uses the independent natural codec without borrowing program storage.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len:
    # Only the explicitly encoded prefix belongs to the output.
    bytes.add(encoded.bytes[index])

proc captureOwner(parts: openArray[seq[byte]], jumps: openArray[uint32] = []): ProgramResult[Program] =
  ## Explicit instruction boundaries support long blocks and saturated operands without a production assembler.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    # Caller-provided operand bytes never become instruction boundaries.
    starts.add(code.len)
    for value in part: code.add(value)
  var bytes: seq[byte] = @[]
  appendNatural(bytes, uint64(jumps.len))
  bytes.add(if jumps.len == 0: 0'u8 else: 4'u8)
  appendNatural(bytes, uint64(code.len))
  for target in jumps:
    # Fixed four-byte table entries are independent of operand decoding and may deliberately name invalid code targets.
    for shift in 0..<4: bytes.add(byte((uint64(target) shr (shift*8)) and 255))
  for value in code: bytes.add(value)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts:
    # Mark the original opcode positions only.
    mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for value in mask: bytes.add(value)
  let decoded = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(65536),
      JumpCountLimit(1024))
  decoded

proc owner(parts: openArray[seq[byte]], jumps: openArray[uint32] = []): Program =
  ## Positive fixtures must retain genuine source admission; malformed fixtures inspect captureOwner directly.
  let decoded = captureOwner(parts, jumps)
  assert decoded.error == ProgramError.None
  decoded.value


when defined(pvmArm64Jit):
  var guardedLoadCases = 0
  when not defined(pvmArm64JitRefuse):
    for destination in 0..<13:
      for addressSlot in 0..<13:
        # Every decoded alias pair must compute its address before overwriting the loaded register.
        let source = owner([@[130'u8, byte(addressSlot*16+destination), 0, 0, 0, 0], @[0'u8]])
        let decoded = instruction(source, CodeAddress(0))
        assert decoded.error == ProgramError.None
        let slots = instructionRegisters(decoded)
        assert int(slots.aIndex) == destination and int(slots.bIndex) == addressSlot
        let memoryJit = newArmJit()
        assert armEntry(memoryJit, 0, 1) == 0
        var memoryBody = default(ArmBlock)
        var memoryWords = armMemoryInstructions(memoryBody, slots, 0, 37)
        assert publishArmEntry(memoryJit, 0, 37, 1, memoryWords)
        var literalBytes = default(array[16, byte])
        for at in 0..<16: literalBytes[at] = byte(at)
        for selectedRegion in 0..<3:
          var descriptors = default(array[3, array[3, uint64]])
          descriptors[selectedRegion] = [65536'u64, 9'u64, cast[uint64](addr literalBytes[0])]
          var input = default(RegisterFile)
          for slot in 0..<13: input[slot] = RegisterValue(0x1122334455667788'u64+uint64(slot))
          input[addressSlot] = RegisterValue(65539)
          let original = input
          assert callArmMemory(memoryJit, 0, input, descriptors) == 37
          for slot in 0..<13:
            # A successful unaligned little-endian load publishes exactly its own destination.
            assert input[slot] == (if slot == destination: RegisterValue(
                0x0a09080706050403'u64) else: original[slot])
          descriptors = default(array[3, array[3, uint64]])
          input = original
          assert callArmMemory(memoryJit, 0, input, descriptors) == high(uint32)
          assert input == original
          inc guardedLoadCases
  echo "ARM_GUARDED_LOAD_LITERAL_CASES,", guardedLoadCases
  var readSpanLiteralCases = 0
  when not defined(pvmArm64JitRefuse):
    for destination in 0..<13:
      for addressSlot in 0..<13:
        # Derived addresses exercise all first-read aliases while arithmetic deliberately destroys X1 scratch.
        let bridge = (destination+1) mod 13
        let last = (destination+2) mod 13
        let fixture = owner([@[130'u8, byte(addressSlot*16+destination), 0, 0, 0, 0],
          @[149'u8, byte(destination*16+bridge), 9],
          @[130'u8, byte(bridge*16+last), 0, 0, 0, 0],
          @[149'u8, byte(last*16+last), 1], @[0'u8]])
        var span = default(ArmReadSpan)
        emitArmRead(span, instructionRegisters(instruction(fixture, CodeAddress(0))), 0)
        emitArmReadArithmetic(span, 149, instructionRegisters(instruction(fixture, CodeAddress(6))), 9)
        emitArmRead(span, instructionRegisters(instruction(fixture, CodeAddress(9))), 0)
        emitArmReadArithmetic(span, 149, instructionRegisters(instruction(fixture, CodeAddress(
            15))), 1)
        let jit = newArmJit()
        assert armEntry(jit, 0, 1) == 0
        var words = armReadInstructions(span, 37)
        assert publishArmEntry(jit, 0, 37, 4, words)
        var bytes = default(array[64, byte])
        for selectedRegion in 0..<3:
          for refusal in 0..<3:
            # A later refusal must roll back the successful first load and its arithmetic; an early refusal is identical.
            let firstValue = if refusal == 2: 65526'u64 else: 65544'u64
            for at in 0..<8:
              bytes[3+at] = byte((firstValue shr (at*8)) and 255)
              bytes[17+at] = byte((0x9988776655443322'u64 shr (at*8)) and 255)
            var regions = default(array[3, array[3, uint64]])
            regions[selectedRegion] = [65536'u64, 57'u64, cast[uint64](addr bytes[0])]
            var registers = default(RegisterFile)
            for slot in 0..<13: registers[slot] = RegisterValue(0x123456789abcdef0'u64+uint64(slot))
            registers[addressSlot] = RegisterValue(if refusal == 1: 65535'u64 else: 65539'u64)
            var expected = registers
            if refusal == 0:
              # These independent literal equations include the exact derived address and second load's suffix.
              expected[destination] = RegisterValue(65544)
              expected[bridge] = RegisterValue(65553)
              expected[last] = RegisterValue(0x9988776655443323'u64)
            let operations = jit.operations
            assert callArmMemory(jit, 0, registers, regions) == (if refusal == 0: 37'u32 else: high(uint32))
            assert registers == expected
            assert jit.operations == operations+(if refusal == 0: 4'u64 else: 0'u64)
            inc readSpanLiteralCases
  echo "ARM_READ_SPAN_LITERAL_CASES,", readSpanLiteralCases
  var readWindowLiteralCases = 0
  when not defined(pvmArm64JitRefuse):
    for baseSlot in 0..<13:
      for distance in [0'u32, 8, 4088]:
        for wrapped in [false, true]:
          let first = if wrapped: 0xffffe000'u32 else: 1'u32
          let destination = (baseSlot+1) mod 13
          let fixture = owner([@[130'u8, byte(baseSlot*16+destination), 0, 0, 0, 0],
            @[149'u8, byte(destination*16+destination), 9],
            @[130'u8, byte(baseSlot*16+baseSlot), 0, 0, 0, 0], @[0'u8]])
          var span = default(ArmReadSpan)
          let slots = instructionRegisters(instruction(fixture, CodeAddress(0)))
          beginArmReadWindow(span, slots.bIndex, first, first+distance)
          emitArmWindowRead(span, slots.aIndex, 0)
          emitArmReadArithmetic(span, 149, instructionRegisters(instruction(fixture, CodeAddress(
              6))), 9)
          emitArmWindowRead(span, slots.bIndex, distance)
          let jit = newArmJit()
          assert armEntry(jit, 0, 1) == 0
          var words = armReadInstructions(span, 37)
          assert publishArmEntry(jit, 0, 37, 3, words)
          var bytes = default(array[8192, byte])
          for at in 0..<8192: bytes[at] = byte((at*29+17) mod 256)
          for region in 0..<3:
            for refusal in 0..<7:
              # The exact extent, protected prefix, top wrap and below-region offsets must all refuse without stores.
              var regions = default(array[3, array[3, uint64]])
              let extent = case refusal
                of 2: uint64(distance)
                of 3: uint64(distance)+3
                else: 8185'u64
              if refusal != 1:
                regions[region] = [65536'u64, extent, cast[uint64](addr bytes[0])]
              var registers = default(RegisterFile)
              for slot in 0..<13: registers[slot] = RegisterValue(0x1122334455667788'u64+uint64(slot))
              let address = case refusal
                of 4: 65535'u32
                of 5: 0xfffffff8'u32
                of 6: 32768'u32
                else: 65539'u32
              registers[baseSlot] = RegisterValue(uint64(address-first)+0x100000000'u64)
              let original = registers
              var expected = registers
              if refusal == 0:
                # Expected little-endian bytes are independent of native instructions and survive X1 scratch reuse.
                var early = 0'u64
                var late = 0'u64
                for at in 0..<8:
                  early = early or (uint64(bytes[3+at]) shl (at*8))
                  late = late or (uint64(bytes[3+int(distance)+at]) shl (at*8))
                expected[destination] = RegisterValue(early+9)
                expected[baseSlot] = RegisterValue(late)
              assert callArmMemory(jit, 0, registers, regions) == (if refusal ==
                  0: 37'u32 else: high(uint32))
              assert registers == expected
              if refusal != 0: assert registers == original
              inc readWindowLiteralCases
  echo "ARM_READ_WINDOW_LITERAL_CASES,", readWindowLiteralCases
  let probeOwner = newArmJit()
  assert armEntry(probeOwner, 0, 1) == 0
  armStartProbe(probeOwner, 0)
  for visit in 0..<8:
    # Discovery expires at the exact bounded visit and never creates executable code or native calls itself.
    assert armFinishProbe(probeOwner, 0) == (visit == 7)
    assert armEntry(probeOwner, 0, 1) == 0
  assert probeOwner.fragments == 0 and probeOwner.calls == 0
  var constantCases = 0
  var regionConstantCases = 0
  for destination in 0..<13:
    # Each original decoded destination exercises actual emitted code; constants include high-halfword and negative values.
    var operand = @[20'u8, byte(destination)]
    for padding in 0..<23: operand.add(0'u8)
    let source = owner([operand, @[0'u8]])
    let decoded = instruction(source, CodeAddress(0))
    assert decoded.error == ProgramError.None, "constant decode"
    let slots = instructionRegisters(decoded)
    assert int(slots.destinationIndex) == destination, "constant decoded destination"
    var constants = @[0'u64, 1'u64, 65535'u64, 65536'u64,
      0x8000000000000000'u64, 0x0000123400000000'u64,
      0xffffffffffffffff'u64, 0xfffffffffffffffe'u64,
      0xffffffffffff1234'u64, 0x1234ffffffffffff'u64,
      0xffff0000ffff0000'u64, 0x123456789abcdef0'u64]
    for pattern in 0..<81:
      # Enumerate every four-halfword mixture of zero, ones and a nontrivial value independently of emitter policy.
      var digits = pattern
      var value = 0'u64
      for half in 0..<4:
        let part = case digits mod 3
          of 0: 0'u64
          of 1: 65535'u64
          else: 0x1234'u64
        value = value or (part shl (half*16))
        digits = digits div 3
      constants.add(value)
    let jit = newArmJit()
    assert armEntry(jit, 0, 1) == 0, "constant entry admission"
    for compact in [false, true]:
      for value in constants:
        # Poison all incoming registers; the selected slot must be defined in full and every other slot preserved.
        var fragment = if compact: newArmRegionBody() else: default(ArmBlock)
        emitArmOperation(fragment, 20, slots, value)
        var words = armInstructions(fragment)
        assert words.len >= 2 and words.len <= 5, "constant word extent"
        if not compact: assert words.len == 5
        elif value in [0'u64, 1, 65535, 65536, 0x8000000000000000'u64,
            0x0000123400000000'u64, high(uint64), high(uint64)-1]:
          assert words.len == 2
        let published = publishArmEntry(jit, 0, 1, 1, words)
        when defined(pvmArm64JitRefuse):
          assert not published
        else:
          assert published, "constant publication"
          var registers = default(RegisterFile)
          for slot in 0..<13: registers[slot] = RegisterValue(high(uint64)-uint64(slot))
          assert callArmEntry(jit, 0, registers) == 1, "constant continuation"
          for slot in 0..<13:
            let expected = RegisterValue(if slot == destination: value else: high(uint64)-uint64(slot))
            if registers[slot] != expected:
              echo "ARM_CONSTANT_VALUE,", destination, ",", value, ",", slot, ",", uint64(registers[
                  slot]), ",", uint64(expected)
              assert false, "native constant value"
        if compact: inc regionConstantCases
        else: inc constantCases
  echo "ARM_CONSTANT_CASES,", constantCases
  echo "ARM_REGION_CONSTANT_CASES,", regionConstantCases

  const highProducts = [
    # Columns A,B,signed*signed,unsigned*unsigned,signed*unsigned were frozen from independent unbounded integers.
    [0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000000'u64, 0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000000'u64, 0x0000000000000002'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000000'u64, 0x7fffffffffffffff'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000000'u64, 0x8000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000000'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000000'u64, 0x0000000100000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000000'u64, 0xdeadbeef12345678'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000001'u64, 0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000001'u64, 0x0000000000000002'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000001'u64, 0x7fffffffffffffff'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000001'u64, 0x8000000000000000'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000001'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000001'u64, 0x0000000100000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000001'u64, 0xdeadbeef12345678'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000002'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000002'u64, 0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000002'u64, 0x0000000000000002'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000002'u64, 0x7fffffffffffffff'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000002'u64, 0x8000000000000000'u64, 0xffffffffffffffff'u64, 0x0000000000000001'u64,
        0x0000000000000001'u64],
    [0x0000000000000002'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0x0000000000000001'u64,
        0x0000000000000001'u64],
    [0x0000000000000002'u64, 0x0000000100000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000000000002'u64, 0xdeadbeef12345678'u64, 0xffffffffffffffff'u64, 0x0000000000000001'u64,
        0x0000000000000001'u64],
    [0x7fffffffffffffff'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x7fffffffffffffff'u64, 0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x7fffffffffffffff'u64, 0x0000000000000002'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x7fffffffffffffff'u64, 0x7fffffffffffffff'u64, 0x3fffffffffffffff'u64, 0x3fffffffffffffff'u64,
        0x3fffffffffffffff'u64],
    [0x7fffffffffffffff'u64, 0x8000000000000000'u64, 0xc000000000000000'u64, 0x3fffffffffffffff'u64,
        0x3fffffffffffffff'u64],
    [0x7fffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0x7ffffffffffffffe'u64,
        0x7ffffffffffffffe'u64],
    [0x7fffffffffffffff'u64, 0x0000000100000001'u64, 0x0000000080000000'u64, 0x0000000080000000'u64,
        0x0000000080000000'u64],
    [0x7fffffffffffffff'u64, 0xdeadbeef12345678'u64, 0xef56df77891a2b3c'u64, 0x6f56df77891a2b3b'u64,
        0x6f56df77891a2b3b'u64],
    [0x8000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x8000000000000000'u64, 0x0000000000000001'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64,
        0xffffffffffffffff'u64],
    [0x8000000000000000'u64, 0x0000000000000002'u64, 0xffffffffffffffff'u64, 0x0000000000000001'u64,
        0xffffffffffffffff'u64],
    [0x8000000000000000'u64, 0x7fffffffffffffff'u64, 0xc000000000000000'u64, 0x3fffffffffffffff'u64,
        0xc000000000000000'u64],
    [0x8000000000000000'u64, 0x8000000000000000'u64, 0x4000000000000000'u64, 0x4000000000000000'u64,
        0xc000000000000000'u64],
    [0x8000000000000000'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64, 0x7fffffffffffffff'u64,
        0x8000000000000000'u64],
    [0x8000000000000000'u64, 0x0000000100000001'u64, 0xffffffff7fffffff'u64, 0x0000000080000000'u64,
        0xffffffff7fffffff'u64],
    [0x8000000000000000'u64, 0xdeadbeef12345678'u64, 0x10a9208876e5d4c4'u64, 0x6f56df77891a2b3c'u64,
        0x90a9208876e5d4c4'u64],
    [0xffffffffffffffff'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0xffffffffffffffff'u64, 0x0000000000000001'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64,
        0xffffffffffffffff'u64],
    [0xffffffffffffffff'u64, 0x0000000000000002'u64, 0xffffffffffffffff'u64, 0x0000000000000001'u64,
        0xffffffffffffffff'u64],
    [0xffffffffffffffff'u64, 0x7fffffffffffffff'u64, 0xffffffffffffffff'u64, 0x7ffffffffffffffe'u64,
        0xffffffffffffffff'u64],
    [0xffffffffffffffff'u64, 0x8000000000000000'u64, 0x0000000000000000'u64, 0x7fffffffffffffff'u64,
        0xffffffffffffffff'u64],
    [0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64, 0xfffffffffffffffe'u64,
        0xffffffffffffffff'u64],
    [0xffffffffffffffff'u64, 0x0000000100000001'u64, 0xffffffffffffffff'u64, 0x0000000100000000'u64,
        0xffffffffffffffff'u64],
    [0xffffffffffffffff'u64, 0xdeadbeef12345678'u64, 0x0000000000000000'u64, 0xdeadbeef12345677'u64,
        0xffffffffffffffff'u64],
    [0x0000000100000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000100000001'u64, 0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000100000001'u64, 0x0000000000000002'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0x0000000100000001'u64, 0x7fffffffffffffff'u64, 0x0000000080000000'u64, 0x0000000080000000'u64,
        0x0000000080000000'u64],
    [0x0000000100000001'u64, 0x8000000000000000'u64, 0xffffffff7fffffff'u64, 0x0000000080000000'u64,
        0x0000000080000000'u64],
    [0x0000000100000001'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0x0000000100000000'u64,
        0x0000000100000000'u64],
    [0x0000000100000001'u64, 0x0000000100000001'u64, 0x0000000000000001'u64, 0x0000000000000001'u64,
        0x0000000000000001'u64],
    [0x0000000100000001'u64, 0xdeadbeef12345678'u64, 0xffffffffdeadbeee'u64, 0x00000000deadbeef'u64,
        0x00000000deadbeef'u64],
    [0xdeadbeef12345678'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
        0x0000000000000000'u64],
    [0xdeadbeef12345678'u64, 0x0000000000000001'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64,
        0xffffffffffffffff'u64],
    [0xdeadbeef12345678'u64, 0x0000000000000002'u64, 0xffffffffffffffff'u64, 0x0000000000000001'u64,
        0xffffffffffffffff'u64],
    [0xdeadbeef12345678'u64, 0x7fffffffffffffff'u64, 0xef56df77891a2b3c'u64, 0x6f56df77891a2b3b'u64,
        0xef56df77891a2b3c'u64],
    [0xdeadbeef12345678'u64, 0x8000000000000000'u64, 0x10a9208876e5d4c4'u64, 0x6f56df77891a2b3c'u64,
        0xef56df77891a2b3c'u64],
    [0xdeadbeef12345678'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64, 0xdeadbeef12345677'u64,
        0xdeadbeef12345678'u64],
    [0xdeadbeef12345678'u64, 0x0000000100000001'u64, 0xffffffffdeadbeee'u64, 0x00000000deadbeef'u64,
        0xffffffffdeadbeee'u64],
    [0xdeadbeef12345678'u64, 0xdeadbeef12345678'u64, 0x04564f341cb0720d'u64, 0xc1b1cd1241191efd'u64,
        0xe3040e232ee4c885'u64],
  ]
  var highCases = 0
  for opcode in 213'u8..217'u8:
    let jit = newArmJit()
    assert armEntry(jit, 0, 1) == 0
    for vector in highProducts:
      for alias in [[0, 1, 2], [0, 1, 0], [0, 1, 1], [1, 0, 0], [1, 0, 1], [12, 12, 12]]:
        # Distinct sources cover D=A/D=B and swapped coordinates; equal-source aliases use only equal-value vectors.
        if alias[0] == alias[1] and vector[0] != vector[1]: continue
        let source = owner([@[opcode, byte(alias[0]+alias[1]*16), byte(alias[2])], @[0'u8]])
        let slots = instructionRegisters(instruction(source, CodeAddress(0)))
        var fragment = default(ArmBlock)
        emitArmOperation(fragment, opcode, slots, 0)
        var words = armInstructions(fragment)
        let published = publishArmEntry(jit, 0, 1, 1, words)
        when defined(pvmArm64JitRefuse):
          assert not published
        else:
          assert published
          var registers = default(RegisterFile)
          for slot in 0..<13: registers[slot] = RegisterValue(0x55aa00ff12340000'u64+uint64(slot))
          registers[slots.aIndex] = RegisterValue(vector[0])
          registers[slots.bIndex] = RegisterValue(vector[1])
          let original = registers
          let expected = if opcode <= 215: vector[int(opcode)-211]
            elif opcode == 216: uint64(vector[0] < vector[1])
            else: uint64((vector[0] xor 0x8000000000000000'u64) < (vector[
                1] xor 0x8000000000000000'u64))
          assert callArmEntry(jit, 0, registers) == 1
          for slot in 0..<13:
            let wanted = if slot == int(slots.destinationIndex): RegisterValue(
                expected) else: original[slot]
            if registers[slot] != wanted:
              echo "ARM_HIGH_MISMATCH,", opcode, ",", vector[0], ",", vector[1], ",", slot
              assert false, "independent high-product/comparison value"
        inc highCases
  var compareCases = 0
  for opcode in [136'u8, 137, 142, 143]:
    let jit = newArmJit()
    assert armEntry(jit, 0, 1) == 0
    for raw in [0'u32, 1, 2, 0x7fffffff'u32, 0x80000000'u32, 0xffffffff'u32]:
      let immediate = uint64(raw) or (if (raw and 0x80000000'u32) !=
          0: 0xffffffff00000000'u64 else: 0'u64)
      for value in [0'u64, 1, 2, 0x7fffffff'u64, 0x80000000'u64, 0x7fffffffffffffff'u64,
          0x8000000000000000'u64, 0xffffffff80000000'u64, high(uint64)]:
        for alias in [false, true]:
          # Decode all four immediate octets; write A may alias the original B input without retaining a stale flag/value.
          var part = @[opcode, byte(if alias: 0x11 else: 0x12)]
          for shift in 0..<4: part.add(byte((uint64(raw) shr (shift*8)) and 255))
          let source = owner([part, @[0'u8]])
          let slots = instructionRegisters(instruction(source, CodeAddress(0)))
          var fragment = default(ArmBlock)
          emitArmOperation(fragment, opcode, slots, immediate)
          var words = armInstructions(fragment)
          let published = publishArmEntry(jit, 0, 1, 1, words)
          when defined(pvmArm64JitRefuse):
            assert not published
          else:
            assert published
            var registers = default(RegisterFile)
            for slot in 0..<13: registers[slot] = RegisterValue(high(uint64)-uint64(slot))
            registers[slots.bIndex] = RegisterValue(value)
            let original = registers
            let left = if opcode in [137'u8, 143]: value xor 0x8000000000000000'u64 else: value
            let right = if opcode in [137'u8, 143]: immediate xor 0x8000000000000000'u64 else: immediate
            let expected = uint64(if opcode in [142'u8, 143]: left > right else: left < right)
            assert callArmEntry(jit, 0, registers) == 1
            for slot in 0..<13:
              let wanted = if slot == int(slots.destinationIndex): RegisterValue(
                  expected) else: original[slot]
              assert registers[slot] == wanted, "independent immediate comparison and untouched registers"
          inc compareCases
  echo "ARM_HIGH_CASES,", highCases
  echo "ARM_COMPARE_CASES,", compareCases

  var nativeCases = 0
  for opcode in 0..255:
    if not supportedArmOpcode(byte(opcode)): continue
    for pattern in [0'u8, 17, 128, 255]:
      var part = @[byte(opcode)]
      for position in 0..<24: part.add(pattern)
      let source = owner([part, part, part, part, @[0'u8]])
      let prepared = newFlatPlan(source, GasCycleLimit(100000))
      for seed in [0'u64, 31, 32, 63, 64, 127, 0x80000000'u64, 0xffffffff'u64,
          0x8000000000000000'u64, high(uint64)]:
        # The independent register evaluator has no code-generation path or resident-register analysis.
        var original = default(RegisterFile)
        for slot in 0..<13: original[slot] = RegisterValue(seed xor uint64(slot))
        let first = evaluateRegisters(source, CodeAddress(0), original)
        assert first.error == RegisterError.None
        let second = evaluateRegisters(source, CodeAddress(25), first.value)
        assert second.error == RegisterError.None
        let third = evaluateRegisters(source, CodeAddress(50), second.value)
        assert third.error == RegisterError.None
        let fourth = evaluateRegisters(source, CodeAddress(75), third.value)
        assert fourth.error == RegisterError.None
        let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: original)
        var frame = newFlatFrame(prepared, [], info)
        runFlat(frame, 100)
        assert frame.reason == StepError.None and frame.exit == StepExit.Panic
        for slot in 0..<13:
          if frame.info.registers[slot] != fourth.value[slot]:
            echo "NATIVE_MISMATCH,", opcode, ",", pattern, ",", seed, ",", slot
            assert false, "native register lowering differs from evaluator"
        let coverage = flatArmStatistics(frame)
        when defined(pvmArm64JitRefuse):
          assert coverage[2] == 0
        else:
          assert coverage[2] == 4
        inc nativeCases
  echo "ARM_REGISTER_CASES,", nativeCases

var nativeOperations = 0'u64
var cases = 0
for pattern in [0'u8, 17, 128, 255]:
  var parts: seq[seq[byte]] = @[]
  for index in 0..<72:
    # Mixed destinations include full aliases and saturated IDs; large padding admits exact decoder-selected immediates.
    let opcodes = [132'u8, 133, 134, 149, 200, 201]
    var part = @[opcodes[index mod 6]]
    for byteIndex in 0..<24: part.add(pattern)
    parts.add(part)
  parts.add(@[0'u8])
  let program = owner(parts)
  let plan = newFlatPlan(program, GasCycleLimit(100000))
  let empty = captureMemory([], PageLimit(2)).value
  for seed in [0'u64, high(uint64), 0x8000000000000000'u64, 0x123456789abcdef0'u64]:
    for paid in [false, true]:
      for gas in [0'u64, 1, 1000]:
        var registers = default(RegisterFile)
        for slot in 0..<13: registers[slot] = RegisterValue(seed xor uint64(slot))
        let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(gas), registers: registers,
            blockCharged: paid)
        let source = captureMachine(program, empty, initial).value
        var frame = newFlatFrame(plan, [], initial)
        for budget in [0'u64, 1, 2, 7, 35, 36, 37, 38, 63, 64, 65, 71, 72, 73, 74, 100]:
          # Reuse compiled fragments around partial barriers and zero/low gas, without retaining mutable registers.
          var current = source
          var expectedExit = StepExit.Continued
          var reason = StepError.StepLimitExceeded
          for attempted in 0'u64..<budget:
            let next = stepOnce(current, GasCycleLimit(100000))
            assert next.error == StepError.None
            current = next.value.machine
            expectedExit = next.value.exit
            if expectedExit != StepExit.Continued:
              reason = StepError.None
              break
          resetFlatFrame(frame, initial)
          runFlat(frame, budget)
          let wanted = machineInfo(current).value
          assert frame.reason == reason and frame.exit == expectedExit, "reason/exit"
          # Ordinary execution normalizes halt/panic PC to zero; stepOnce deliberately retains its terminal source site.
          let wantedPc = if expectedExit in [StepExit.Halt, StepExit.Panic]: 0'u64 else: uint64(wanted.pc)
          assert uint64(frame.info.pc) == wantedPc, "PC"
          assert uint64(frame.info.gas) == uint64(wanted.gas), "gas"
          assert uint64(frame.info.gasDeficit) == uint64(wanted.gasDeficit), "deficit"
          assert frame.info.blockCharged == wanted.blockCharged, "charged"
          for slot in 0..<13: assert frame.info.registers[slot] == wanted.registers[slot], "register"
          checkFlatSource(frame)
          inc cases
        when defined(pvmArm64Jit):
          let observed = flatArmStatistics(frame)
          nativeOperations+=observed[2]
when defined(pvmArm64Jit):
  # A checked matrix that only falls back is not evidence that emitted instructions executed.
  when defined(pvmArm64JitRefuse):
    assert nativeOperations == 0
  else:
    assert nativeOperations > 0
  echo "ARM_WITNESS,", cases, ",", nativeOperations
else:
  echo "INTERPRETER_WITNESS,", cases

# Stream transfer drops native entries before changing emission history; the restored checked stream remains reusable.
let transferProgram = owner([@[200'u8, 0, 0], @[201'u8, 0, 0], @[200'u8, 0, 0], @[201'u8, 0, 0], @[0'u8]])
let transferPlan = newFlatPlan(transferProgram, GasCycleLimit(100000))
let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
var first = newFlatFrame(transferPlan, [], initial)
runFlat(first, 100)
when defined(pvmArm64Jit):
  let live = flatArmStatistics(first)
  when defined(pvmArm64JitRefuse):
    assert live[0] == 0 and live[1] == 0
  else:
    assert live[0] == 1 and live[1] == 1 and live[2] == 4
var stream = takeFlatStream(first)
var second = newFlatFrame(transferPlan, [], initial)
restoreFlatStream(second, stream)
runFlat(second, 100)
echo "TRANSFER,", second.exit, ",", second.reason
assert second.exit == StepExit.Panic and second.reason == StepError.None
checkFlatSource(second)
when defined(pvmArm64Jit):
  let transferred = flatArmStatistics(second)
  echo "TRANSFER_STATS,", transferred[0], ",", transferred[1]
  when defined(pvmArm64JitRefuse):
    assert transferred[0] == 0 and transferred[1] == 0
  else:
    assert transferred[0] == 1 and transferred[1] == 2
    assert transferred[2] == 8
  var retained = takeFlatStream(second)
  let retainedNodes = streamNodes(retained)
  var foreign = newFlatFrame(newFlatPlan(transferProgram, GasCycleLimit(100000)), [], initial)
  restoreFlatStream(foreign, retained)
  runFlat(foreign, 100)
  assert foreign.reason == StepError.InvalidPreparedProgram
  assert streamNodes(retained) == retainedNodes
  restoreFlatStream(second, retained)
  resetFlatFrame(second, initial)
  runFlat(second, 100)
  assert second.exit == StepExit.Panic and second.reason == StepError.None
  when not defined(pvmArm64JitRefuse):
    assert flatArmStatistics(second)[1] == 3
  # Whole-memory replacement keeps exact-plan native entries while discarding invocation-local bytes and registers.
  replaceFlatMemory(second, [], initial)
  runFlat(second, 100)
  assert second.exit == StepExit.Panic and second.reason == StepError.None
  when not defined(pvmArm64JitRefuse):
    assert flatArmStatistics(second)[0] == 1 and flatArmStatistics(second)[1] == 4
  let retired = flatArmStatistics(first)
  echo "RETIRED_STATS,", retired[0], ",", retired[1]
  assert retired[0] == 0 and retired[1] == 0
# A final arithmetic opcode lacking genuine fallthrough is refused at source admission, before JIT authority exists.
let truncatedProgram = captureOwner([@[200'u8, 0, 0], @[201'u8, 0, 0]])
echo "TRUNCATED_ADMISSION,", truncatedProgram.error
assert truncatedProgram.error == ProgramError.InvalidProgram

# Two-operation runs now deliberately remain interpreted; admission still preserves their exact values and exit.
let shortProgram = owner([@[200'u8, 0, 0], @[201'u8, 0, 0], @[0'u8]])
var shortFrame = newFlatFrame(newFlatPlan(shortProgram, GasCycleLimit(100000)), [], initial)
runFlat(shortFrame, 100)
assert shortFrame.reason == StepError.None and shortFrame.exit == StepExit.Panic
when defined(pvmArm64Jit):
  let short = flatArmStatistics(shortFrame)
  assert short[0] == 0 and short[1] == 0

when defined(pvmArm64Jit):
  var branchPredicates = 0
  var regionBranchPredicates = 0
  for opcode in 0..255:
    if byte(opcode) notin {81'u8..90'u8, 170'u8..175'u8}: continue
    for pattern in [0'u8, 17, 128, 255]:
      var part = @[byte(opcode)]
      for position in 0..<24: part.add(pattern)
      let program = owner([part, @[0'u8]])
      let decoded = instruction(program, CodeAddress(0))
      assert decoded.error == ProgramError.None
      let slots = instructionRegisters(decoded)
      let low = uint64(decoded.value.x) and 0xffffffff'u64
      let immediate = if (low and 0x80000000'u64) != 0: low or 0xffffffff00000000'u64 else: low
      for compact in [false, true]:
        var native = if compact: newArmRegionBody() else: default(ArmBlock)
        emitArmBranch(native, byte(opcode), slots, immediate, 0x12345678'u32, 0x76543210'u32)
        var words = armInstructions(native)
        let jit = newArmJit()
        assert armEntry(jit, 0, 1) == 0
        let published = publishArmEntry(jit, 0, 0, 1, words)
        when defined(pvmArm64JitRefuse):
          assert not published
        else:
          assert published
          for left in [0'u64, 1, 0x80000000'u64, 0xffffffff'u64, 0x7fffffffffffffff'u64,
              0x8000000000000000'u64, high(uint64)]:
            for right in [0'u64, 1, 0x80000000'u64, 0xffffffff'u64, 0x7fffffffffffffff'u64,
                0x8000000000000000'u64, high(uint64)]:
              var original = default(RegisterFile)
              original[slots.aIndex] = RegisterValue(left)
              original[slots.bIndex] = RegisterValue(right)
              let a = uint64(original[slots.aIndex])
              let b = if opcode <= 90: immediate else: uint64(original[slots.bIndex])
              let sa = a xor 0x8000000000000000'u64
              let sb = b xor 0x8000000000000000'u64
              let condition = case opcode
                of 81, 170: a == b
                of 82, 171: a != b
                of 83, 172: a < b
                of 84: a <= b
                of 85, 174: a >= b
                of 86: a > b
                of 87, 173: sa < sb
                of 88: sa <= sb
                of 89, 175: sa >= sb
                else: sa > sb
              let expected = if condition: 0x12345678'u32 else: 0x76543210'u32
              var registers = original
              assert callArmBranch(jit, 0, registers) == expected
              for slot in 0..<13: assert registers[slot] == original[slot]
              if compact: inc regionBranchPredicates
              else: inc branchPredicates
  echo "ARM_BRANCH_PREDICATES,", branchPredicates
  echo "ARM_REGION_BRANCH_PREDICATES,", regionBranchPredicates

  # A full arena must retain the last valid entry after a failed replacement publication.
  let capacity = newArmJit()
  assert armEntry(capacity, 0, 1) == 0
  var pages = newSeq[uint32](1023)
  for position in 0..<pages.len: pages[position] = 0xd65f03c0'u32
  var initialWords = pages
  let admitted = publishArmEntry(capacity, 0, 77, 1, initialWords)
  when defined(pvmArm64JitRefuse):
    assert not admitted
    # A different, previously unmapped coordinate refuses without growing this failed owner's entry map.
    assert armEntry(capacity, 1, 2) == 1
    var retriedWords = @[0xd65f03c0'u32]
    assert not publishArmEntry(capacity, 1, 0, 0, retriedWords)
    let fresh = newArmJit()
    assert armEntry(fresh, 1, 2) == 0
    echo "ARM_REFUSAL_CACHE,1"
  else:
    assert admitted
    var successes = 1
    while true:
      # Distinct unreachable tail words prevent exact-image reuse from hiding physical byte exhaustion.
      assert successes <= 256
      pages[pages.len-1] = 0xd2800001'u32 or (uint32(successes) shl 5)
      var next = pages
      if not publishArmEntry(capacity, 0, 77, 1, next): break
      inc successes
    assert successes == 256
    var capacityRegisters = default(RegisterFile)
    assert callArmEntry(capacity, 0, capacityRegisters) == 77
    # A failed replacement with different metadata must preserve the old code, successor and exact operation count together.
    let beforeOperations = capacity.operations
    var rejectedWords = pages
    assert not publishArmEntry(capacity, 0, 99999, 123, rejectedWords)
    assert callArmEntry(capacity, 0, capacityRegisters) == 77
    assert capacity.operations-beforeOperations == 1
    echo "ARM_REPLACEMENT_REFUSAL,", successes

  when not defined(pvmArm64JitRefuse):
    # One connected publication fits after ordinary leaves exhaust their reserved 1,023-slot budget; total stays 1,024.
    let bounded = newArmJit()
    assert armEntry(bounded, 0, 3) == 0
    for slot in 0..<1023:
      # Distinct scratch-only MOVZ bodies consume actual publication slots, without modifying guest registers.
      var words = @[0xd2800001'u32 or (uint32(slot) shl 5)]
      assert publishArmEntry(bounded, 0, 0, 1, words)
    var refused = @[0xd503201f'u32]
    assert not publishArmEntry(bounded, 0, 0, 1, refused)
    let source = owner([@[131'u8, 0, 1], @[0'u8]])
    let slots = instructionRegisters(instruction(source, CodeAddress(0)))
    var blocks = default(array[3, ArmRegionBlock])
    for index in 0..<3:
      # Independent fixed-cost increment blocks select the next internal header until a quota or gas guard returns.
      var body = default(ArmBlock)
      emitArmOperation(body, 131, slots, 1)
      emitArmBranch(body, 81, slots, 99, 77, uint32((index+1) mod 3))
      blocks[index] = ArmRegionBlock(header: uint32(index), span: 2, operations: 2,
          price: 1, yes: 77, no: uint32((index+1) mod 3), body: move(body))
    assert publishArmRegion(bounded, blocks)
    assert bounded.fragments == 1024
    for budget in [0'u64, 1, 2, 3, 4, 5, 6, 7]:
      for gas in [0'u64, 1, 2, 3, 100]:
        # Literal expected counts do not use the emitter or guest evaluator; all unexecuted registers remain unchanged.
        var registers = default(RegisterFile)
        for slot in 0..<13: registers[slot] = RegisterValue(uint64(slot)*0x100000001'u64)
        let original = registers
        var state = [gas, budget, 0'u64, 0'u64, 0'u64]
        let count = min(gas, budget div 2)
        assert callArmRegion(bounded, registers, state) == uint32(count mod 3)
        assert uint64(registers[0]) == count
        for slot in 1..<13: assert registers[slot] == original[slot]
        assert state[0] == gas-count and state[1] == budget-count*2
        for index in 0..<3:
          let visits = count div 3+uint64(uint64(index) < count mod 3)
          assert state[index+2] == visits
    var finalRefusal = @[0xd503201f'u32]
    assert not publishArmEntry(bounded, 0, 0, 1, finalRefusal, true)
    echo "ARM_REGION_CAPACITY,1024"

    # Two-block regions retain the same five-word ABI with a genuinely inactive third counter lane.
    var pairLiteralCases = 0
    let pairSource = owner([@[131'u8, 0, 1], @[0'u8]])
    let pairSlots = instructionRegisters(instruction(pairSource, CodeAddress(0)))
    for policy in 0..<4:
      let prices = case policy
        of 0: [0'u64, 0'u64]
        of 1: [1'u64, 2'u64]
        of 2: [4095'u64, 4096'u64]
        else: [high(uint64), 0'u64]
      for rotated in [false, true]:
        let pairJit = newArmJit()
        discard armEntry(pairJit, 0, 23)
        var pairBlocks = default(array[3, ArmRegionBlock])
        for index in 0..<2:
          # Literal increments keep branch comparisons away from their external exit for these bounded budgets.
          let phase = if rotated: 1-index else: index
          var body = default(ArmBlock)
          emitArmOperation(body, 131, pairSlots, 1)
          let next = if phase == 0: 22'u32 else: 11'u32
          emitArmBranch(body, 81, pairSlots, 65535, 99, next)
          pairBlocks[index] = ArmRegionBlock(header: (if phase == 0: 11'u32 else: 22'u32),
              span: 2, operations: 2, price: prices[phase], yes: 99, no: next, body: move(body))
        assert publishArmRegion(pairJit, pairBlocks, 2)
        assert armRegionCount(pairJit) == 2
        for gas in [0'u64, 1, 2, 3, 4095, 4096, high(uint64)]:
          for budget in 0'u64..12'u64:
            var registers = default(RegisterFile)
            for slot in 1..<13: registers[slot] = RegisterValue(uint64(slot)+400)
            let original = registers
            var expectedGas = gas
            var expectedBudget = budget
            var phase = if rotated: 1 else: 0
            var visits = default(array[2, uint64])
            while expectedBudget >= 2 and expectedGas >= prices[phase]:
              # This literal source-count/price model does not reuse any native lowering or register evaluator.
              expectedBudget-=2
              expectedGas-=prices[phase]
              inc visits[phase]
              phase = 1-phase
            var state = [gas, budget, 0'u64, 0'u64, 0'u64]
            assert callArmRegion(pairJit, registers, state) == (if phase == 0: 11'u32 else: 22'u32)
            assert state[0] == expectedGas and state[1] == expectedBudget and state[4] == 0
            assert state[2] == visits[if rotated: 1 else: 0]
            assert state[3] == visits[if rotated: 0 else: 1]
            assert uint64(registers[0]) == visits[0]+visits[1]
            for slot in 1..<13: assert registers[slot] == original[slot]
            inc pairLiteralCases
    echo "ARM_TWO_BLOCK_LITERAL_CASES,", pairLiteralCases

    # Price width and source-budget width are independent: exercise both sides of the immediate boundary and full u64.
    var priceCases = 0
    for price in [0'u64, 1, 4095, 4096, 0x100000000'u64, high(uint64)]:
      let charged = newArmJit()
      assert armEntry(charged, 0, 3) == 0
      var pricedBlocks = default(array[3, ArmRegionBlock])
      for index in 0..<3:
        # A literal ninety-nine-increment exit bounds even zero-price execution with a maximal source budget.
        var body = newArmRegionBody()
        emitArmOperation(body, 131, slots, 1)
        emitArmBranch(body, 81, slots, 99, 77, uint32((index+1) mod 3))
        pricedBlocks[index] = ArmRegionBlock(header: uint32(index), span: 2, operations: 2,
            price: price, yes: 77, no: uint32((index+1) mod 3), body: move(body))
      assert publishArmRegion(charged, pricedBlocks)
      for gas in [0'u64, 1, 4094, 4095, 4096, 8190, 8192, 0x100000000'u64, high(uint64)]:
        for budget in [0'u64, 1, 2, 5, 197, 198, 199, 0x100000000'u64, high(uint64)]:
          # Literal arithmetic independently predicts guarded work, with division proving the charge product cannot wrap.
          var registers = default(RegisterFile)
          var state = [gas, budget, 0'u64, 0'u64, 0'u64]
          let affordable = if price == 0: 99'u64 else: min(99'u64, gas div price)
          let count = min(affordable, budget div 2)
          let target = if count == 99: 77'u32 else: uint32(count mod 3)
          assert callArmRegion(charged, registers, state) == target
          assert uint64(registers[0]) == count
          for slot in 1..<13: assert uint64(registers[slot]) == 0
          assert state[0] == gas-count*price and state[1] == budget-count*2
          for index in 0..<3:
            assert state[index+2] == count div 3+uint64(uint64(index) < count mod 3)
          inc priceCases
    echo "ARM_REGION_PRICE_CASES,", priceCases

    # All eight conditional orientations exercise native fall-through/inversion without changing the finite loop equation.
    var layoutCases = 0
    for mask in 0..<8:
      let arranged = newArmJit()
      assert armEntry(arranged, 0, 3) == 0
      var oriented = default(array[3, ArmRegionBlock])
      for index in 0..<3:
        var body = newArmRegionBody()
        emitArmOperation(body, 131, slots, 1)
        let next = uint32((index+1) mod 3)
        let inverted = (mask and (1 shl index)) != 0
        let yes = if inverted: next else: 77'u32
        let no = if inverted: 77'u32 else: next
        emitArmBranch(body, if inverted: 82'u8 else: 81'u8, slots, 99, yes, no)
        oriented[index] = ArmRegionBlock(header: uint32(index), span: 2, operations: 2,
            price: 1, yes: yes, no: no, body: move(body))
      assert publishArmRegion(arranged, oriented)
      for gas in [0'u64, 1, 2, 3, 98, 99, 100, high(uint64)]:
        for budget in [0'u64, 1, 2, 3, 4, 5, 6, 7, 197, 198, high(uint64)]:
          # Literal exit and visit equations are independent of emitted branch layout and condition encodings.
          var registers = default(RegisterFile)
          var state = [gas, budget, 0'u64, 0'u64, 0'u64]
          let count = min(99'u64, min(gas, budget div 2))
          let target = if count == 99: 77'u32 else: uint32(count mod 3)
          assert callArmRegion(arranged, registers, state) == target
          assert uint64(registers[0]) == count
          for slot in 1..<13: assert uint64(registers[slot]) == 0
          assert state[0] == gas-count and state[1] == budget-count*2
          for index in 0..<3:
            assert state[index+2] == count div 3+uint64(uint64(index) < count mod 3)
          inc layoutCases
    echo "ARM_REGION_LAYOUT_CASES,", layoutCases

proc verifyControl(frame: var FlatFrame, program: Program, info: MachineInfo, budget: uint64,
    images: openArray[PageImage] = []) =
  ## Bounded single-step execution independently checks charged prefixes, target PCs and terminal normalization.
  let memory = captureMemory(images, PageLimit(uint32(max(2, images.len)))).value
  var expected = captureMachine(program, memory, info).value
  var exit = StepExit.Continued
  var reason = StepError.StepLimitExceeded
  var consumed = 0'u64
  var wantedHost = HostCallId(0)
  var wantedFault = PageAddress(0)
  var wantedHostPc = CodeAddress(0)
  for attempted in 0'u64..<budget:
    let attemptedPc = machineInfo(expected).value.pc
    let next = stepOnce(expected, GasCycleLimit(100000))
    assert next.error == StepError.None
    expected = next.value.machine
    exit = next.value.exit
    if exit != StepExit.OutOfGas: inc consumed
    if exit == StepExit.Host:
      # Psi_1 advances the published host PC; recursive suspension retains the attempted instruction.
      wantedHost = next.value.hostCall
      wantedHostPc = attemptedPc
    if exit == StepExit.Fault: wantedFault = next.value.faultPage
    if exit != StepExit.Continued:
      reason = StepError.None
      break
  resetFlatFrame(frame, info)
  runFlat(frame, budget)
  let wanted = machineInfo(expected).value
  if frame.reason != reason or frame.exit != exit:
    echo "CONTROL_EXIT,", budget, ",", reason, ",", exit, ",", frame.reason, ",", frame.exit
  assert frame.reason == reason and frame.exit == exit
  if frame.remaining != budget-consumed:
    echo "REMAINING,", budget, ",", consumed, ",", frame.remaining, ",", exit
  assert frame.remaining == budget-consumed
  if exit == StepExit.Host:
    assert frame.hostCall == wantedHost
  if exit == StepExit.Fault: assert frame.faultPage == wantedFault
  let pc = if exit in [StepExit.Halt, StepExit.Panic]: 0'u64
    elif exit == StepExit.Host: uint64(wantedHostPc)
    else: uint64(wanted.pc)
  if uint64(frame.info.pc) != pc: echo "CONTROL_PC,", uint64(frame.info.pc), ",", pc
  assert uint64(frame.info.pc) == pc
  assert frame.info.gas == wanted.gas and frame.info.gasDeficit == wanted.gasDeficit
  assert frame.info.blockCharged == wanted.blockCharged
  for slot in 0..<13: assert frame.info.registers[slot] == wanted.registers[slot]
  checkFlatSource(frame)
  if images.len != 0:
    # Load-only work must preserve all private bytes and permission metadata, including inaccessible pages.
    let published = flatMemorySnapshot(frame)
    for image in images:
      let actual = pageImage(published, image.index)
      assert actual.error == MachineError.None
      assert actual.value.access == image.access and actual.value.bytes == image.bytes

var loadCases = 0
for opcode in 124'u8..130'u8:
  for layout in 0..<8:
    var images: seq[PageImage] = @[]
    if layout != 0:
      # Adjacent RO/RW, split permissions, a missing page, an inaccessible page, fragmented RO and the final page.
      var first = PageImage(index: PageIndex(if layout == 7: 1048575'u32 else: 16'u32),
          access: (if layout == 2 or layout == 7: PageAccess.ReadWrite else: PageAccess.ReadOnly),
          bytes: default(array[4096, byte]))
      for at in 0..<4096: first.bytes[at] = byte((at*17+layout) mod 256)
      images.add(first)
      if layout in [1, 2, 3, 4, 6]:
        var second = PageImage(index: PageIndex(if layout == 6: 18'u32 else: 17'u32),
            access: (if layout == 4: PageAccess.Inaccessible elif layout in [2,
                3]: PageAccess.ReadWrite else: PageAccess.ReadOnly),
            bytes: default(array[4096, byte]))
        if second.access != PageAccess.Inaccessible:
          for at in 0..<4096: second.bytes[at] = byte((at*29+layout+91) mod 256)
        images.add(second)
    for destination in [0, 1]:
      for displacement in [0'u32, 7'u32, 0xfffffff8'u32]:
        # A aliases B in one shape; source address calculation must finish before the loaded destination changes.
        var load = @[opcode, byte(0x10+destination)]
        for shift in 0..<4: load.add(byte((uint64(displacement) shr (shift*8)) and 255))
        let program = owner([load, @[149'u8, byte(destination*16+2), 1],
            @[133'u8, 0x23, 0x7f], @[149'u8, 0x34, 0xff], @[0'u8]])
        let plan = newFlatPlan(program, GasCycleLimit(100000))
        let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
        var frame = newFlatFrame(plan, images, initial)
        for address in [0'u64, 65535, 65536, 65537, 69624, 69625, 69631, 69632, 73720, 73721,
            73728, 0xfffffff7'u64, 0xfffffff8'u64, 0xffffffff'u64, 0x100010000'u64, high(uint64)]:
          var input = initial
          for slot in 0..<13: input.registers[slot] = RegisterValue(0x923456789abcdef0'u64+uint64(slot))
          input.registers[1] = RegisterValue(address)
          verifyControl(frame, program, input, 9, images)
          inc loadCases
        for paid in [false, true]:
          for gas in [0'u64, 1, 4, 5, 1000]:
            for budget in 0'u64..6'u64:
              # Reuse an already emitted cache around exact out-of-gas and every partial reservation boundary.
              var input = initial
              input.registers[1] = RegisterValue(if layout == 7: 0xfffff003'u64 else: 65539'u64)
              input.gas = MachineGas(gas)
              input.blockCharged = paid
              verifyControl(frame, program, input, budget, images)
              inc loadCases
        when defined(pvmArm64Jit):
          let stats = flatArmStatistics(frame)
          when defined(pvmArm64JitRefuse):
            assert stats[2] == 0
          else:
            # Valid private maps execute the guarded load plus its three-operation suffix; absent maps preserve checked faults.
            if layout == 0 or opcode != 130: assert stats[2] == 0
            else: assert stats[2] > 0
        # Same-plan replacement and a transferred stream must read the new invocation's word.
        var changed: seq[PageImage] = @[]
        for original in images:
          var image = original
          if image.access != PageAccess.Inaccessible:
            for at in 0..<4096: image.bytes[at] = byte((at*31+layout+7) mod 256)
          changed.add(image)
        let accepted = replaceFlatMemoryChecked(frame, changed, initial)
        assert accepted == FlatError.None
        var input = initial
        input.registers[1] = RegisterValue(if layout == 7: 0xfffff003'u64 else: 65539'u64)
        verifyControl(frame, program, input, 9, changed)
        var cache = takeFlatStream(frame)
        var fresh = newFlatFrame(plan, images, input)
        restoreFlatStream(fresh, cache)
        verifyControl(fresh, program, input, 9, images)
        loadCases+=2

# Folded source instructions and all three price policies retain the same exact head-load reservation semantics.
for folded in [false, true]:
  var parts = @[@[130'u8, 0x10, 0, 0, 0, 0]]
  if folded: parts.add(@[2'u8])
  parts.add(@[149'u8, 0x02, 1])
  parts.add(@[133'u8, 0x23, 0x7f])
  parts.add(@[149'u8, 0x34, 0xff])
  parts.add(@[0'u8])
  let program = owner(parts)
  var image = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly,
      bytes: default(array[4096, byte]))
  for at in 0..<4096: image.bytes[at] = byte((at*43+17) mod 256)
  var input = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
  input.registers[1] = RegisterValue(65539)
  for policy in 0..<3:
    var frame = newFlatFrame(newFlatPlan(program, GasCycleLimit(100000)), [image], input)
    if policy == 1:
      let complete = newGasPlan(program, GasPlanLimits(bytes: GasPlanByteLimit(65536),
          blocks: GasPlanBlockLimit(1024), cycles: GasCycleLimit(100000)))
      assert complete.error == GasPlanError.None
      assert selectFlatPrices(frame, complete.value, default(GasMemo)) == StepError.None
    elif policy == 2:
      let lazy = newGasMemo(program, GasMemoLimits(bytes: GasMemoByteLimit(65536),
          cycles: GasCycleLimit(100000)))
      assert lazy.error == GasMemoError.None
      assert selectFlatPrices(frame, default(GasPlan), lazy.value) == StepError.None
      verifyControl(frame, program, input, 0, [image])
      assert gasMemoInfo(lazy.value).value.pricedBlocks == 0
      verifyControl(frame, program, input, 1, [image])
      assert gasMemoInfo(lazy.value).value.pricedBlocks == 1
    for paid in [false, true]:
      for gas in [0'u64, 1, 4, 5, 6, 1000]:
        for budget in 0'u64..7'u64:
          var bounded = input
          bounded.gas = MachineGas(gas)
          bounded.blockCharged = paid
          verifyControl(frame, program, bounded, budget, [image])
          inc loadCases

echo "ARM_HEAD_LOAD_CASES,", loadCases

var readSpanCases = 0
for layout in 0..<8:
  let base = if layout == 7: 0xfffff000'u64 else: 65536'u64
  for aliased in [false, true]:
    let first = if aliased: 1 else: 0
    let last = if aliased: 2 else: 3
    let program = owner([@[130'u8, byte(0x10+first), 0, 0, 0, 0],
      @[149'u8, byte(first*16+2), 9], @[130'u8, byte(0x20+last), 0, 0, 0, 0],
      @[149'u8, byte(last*16+4), 1], @[0'u8]])
    for target in [0'u64, 65535, base+17, base+4092, base+4096, base+8192,
        0xfffffff8'u64, 0xffffffff'u64]:
      var images: seq[PageImage] = @[]
      if layout != 0:
        # The first read derives the second address; adjacent/split/absent/inaccessible/fragmented maps exercise later guards.
        var page = PageImage(index: PageIndex(uint32(base shr 12)),
          access: (if layout == 2 or layout == 7: PageAccess.ReadWrite else: PageAccess.ReadOnly),
              bytes: default(array[4096, byte]))
        for at in 0..<4096: page.bytes[at] = byte((at*17+layout) mod 256)
        let pointer = target-9'u64
        for at in 0..<8: page.bytes[3+at] = byte((pointer shr (at*8)) and 255)
        images.add(page)
        if layout in [1, 2, 3, 5, 6]:
          var second = PageImage(index: PageIndex(if layout == 6: 18'u32 else: 17'u32),
            access: (if layout == 5: PageAccess.Inaccessible elif layout in [2, 3]:
            PageAccess.ReadWrite else: PageAccess.ReadOnly), bytes: default(array[4096, byte]))
          if second.access != PageAccess.Inaccessible:
            for at in 0..<4096: second.bytes[at] = byte((at*23+79) mod 256)
          images.add(second)
      var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
      info.registers[1] = RegisterValue(base+3+(if aliased: 0x100000000'u64 else: 0'u64))
      for policy in 0..<3:
        let sourcePlan = newFlatPlan(program, GasCycleLimit(100000))
        var frame = newFlatFrame(sourcePlan, images, info)
        if policy == 1:
          let plan = newGasPlan(program, GasPlanLimits(bytes: GasPlanByteLimit(65536),
            blocks: GasPlanBlockLimit(1024), cycles: GasCycleLimit(100000)))
          assert plan.error == GasPlanError.None
          assert selectFlatPrices(frame, plan.value, default(GasMemo)) == StepError.None
        elif policy == 2:
          let memo = newGasMemo(program, GasMemoLimits(bytes: GasMemoByteLimit(65536),
              cycles: GasCycleLimit(100000)))
          assert memo.error == GasMemoError.None
          assert selectFlatPrices(frame, default(GasPlan), memo.value) == StepError.None
        verifyControl(frame, program, info, 100, images)
        when defined(pvmArm64Jit):
          let stats = flatArmStatistics(frame)
          when defined(pvmArm64JitRefuse): assert stats[1] == 0 and stats[2] == 0
          else:
            if layout != 0 and target == base+17:
              # Two reads and their arithmetic use one native handoff, including the derived-address alias.
              assert stats[1] == 1 and stats[2] == 4
        for paid in [false, true]:
          for gas in [0'u64, 1, 4, 5, 6, 1000]:
            for budget in 0'u64..8'u64:
              # Refused speculation replays exact successful prefixes and later fault/PC/gas without double debit.
              var input = info
              input.gas = MachineGas(gas)
              input.blockCharged = paid
              verifyControl(frame, program, input, budget, images)
              inc readSpanCases
        var cache = takeFlatStream(frame)
        var fresh = newFlatFrame(sourcePlan, images, info)
        # Same-plan code retains no descriptor pointer; a new invocation owns fresh bytes and can replace them.
        restoreFlatStream(fresh, cache)
        verifyControl(fresh, program, info, 100, images)
        assert replaceFlatMemoryChecked(fresh, [], info) == FlatError.None
        verifyControl(fresh, program, info, 100)
        readSpanCases+=2

# Multiple guard relocations and publication refusal retain the same exact source semantics at both native caps.
for depth in [2, 3, 16, 32, 63, 64, 65]:
  for badAt in [-1, 0, depth div 2, depth-1]:
    var parts: seq[seq[byte]] = @[]
    for at in 0..<depth:
      # A selected later read faults at the protected prefix after any successful earlier source effects.
      let displacement = if at == badAt: 0xffffffff'u32 else: uint32(at*8)
      var load = @[130'u8, 0x10]
      for shift in 0..<4: load.add(byte((displacement shr (shift*8)) and 255))
      parts.add(load)
    parts.add(@[149'u8, 0x02, 1])
    parts.add(@[133'u8, 0x23, 0x7f])
    parts.add(@[149'u8, 0x34, 0xff])
    parts.add(@[0'u8])
    let program = owner(parts)
    var page = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly,
      bytes: default(array[4096, byte]))
    for at in 0..<4096: page.bytes[at] = byte((at*43+17) mod 256)
    var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
    info.registers[1] = RegisterValue(65536)
    var frame = newFlatFrame(newFlatPlan(program, GasCycleLimit(100000)), [page], info)
    for paid in [false, true]:
      for gas in [0'u64, uint64(depth+3), uint64(depth+4), high(uint64)]:
        for budget in 0..depth+5:
          # Every attempt prefix covers a partial reservation, a complete span and any oversized span's checked fallback.
          var input = info
          input.blockCharged = paid
          input.gas = MachineGas(gas)
          verifyControl(frame, program, input, uint64(budget), [page])
          inc readSpanCases

# Shared windows must conservatively replay fragmented maps and bases changed by either a read or arithmetic.
for shape in 0..<6:
  let first = if shape == 1: 1 else: 0
  let secondBase = if shape == 3: 2 else: 1
  let delta = if shape == 4: 9'u32 elif shape == 5: 0xfffffff8'u32 else: 8'u32
  var second = @[130'u8, byte(secondBase*16+3)]
  for shift in 0..<4: second.add(byte((delta shr (shift*8)) and 255))
  let program = owner([@[130'u8, byte(0x10+first), 0, 0, 0, 0],
    @[149'u8, byte(if shape == 2: 0x11 else: 0x02), 1], second,
    @[149'u8, 0x34, 1], @[0'u8]])
  for split in [false, true]:
    var pages: seq[PageImage] = @[]
    for index in 0..<2:
      # Adjacent read-only/writable pages cannot share a descriptor; the general checked handler still accepts both.
      var page = PageImage(index: PageIndex(uint32(16+index)), access:
        (if split and index == 1: PageAccess.ReadWrite else: PageAccess.ReadOnly),
        bytes: default(array[4096, byte]))
      for at in 0..<4096: page.bytes[at] = byte((at*17+index*3) mod 256)
      pages.add(page)
    for address in [65535'u64, 65536, 69620, 69624, 69628, 73720, 0xfffffff8'u64]:
      var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
      info.registers[1] = RegisterValue(address)
      var frame = newFlatFrame(newFlatPlan(program, GasCycleLimit(100000)), pages, info)
      for paid in [false, true]:
        for gas in [0'u64, 4, 5, 1000]:
          for budget in 0'u64..7'u64:
            # Every refused proof must publish exactly the source prefix's registers, gas, PC, memory and permission state.
            var input = info
            input.blockCharged = paid
            input.gas = MachineGas(gas)
            verifyControl(frame, program, input, budget, pages)
            inc readSpanCases

echo "ARM_READ_SPAN_CONTROL_CASES,", readSpanCases

# A host call changes the map before a static jump revisits the same checked load.
let loadLoop = owner([@[130'u8, 0x10, 0, 0, 0, 0], @[149'u8, 0x02, 1],
  @[130'u8, 0x15, 8, 0, 0, 0], @[133'u8, 0x23, 0x7f], @[149'u8, 0x34, 0xff], @[10'u8, 7],
  @[40'u8, 0xe9, 0xff, 0xff, 0xff]])
var firstWord = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly,
    bytes: default(array[4096, byte]))
for at in 0..<4096: firstWord.bytes[at] = byte((at*7+19) mod 256)
var loadInfo = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
loadInfo.registers[1] = RegisterValue(65539)
var hostLoadFrame = newFlatFrame(newFlatPlan(loadLoop, GasCycleLimit(100000)), [firstWord], loadInfo)
runFlat(hostLoadFrame, 100)
assert hostLoadFrame.reason == StepError.None and hostLoadFrame.exit == StepExit.Host
let originalHostMemory = observeFlatHostMemory(hostLoadFrame)
var secondWord = firstWord
for at in 0..<4096: secondWord.bytes[at] = byte((at*13+71) mod 256)
let changedHostMemory = captureMemory([secondWord], PageLimit(2)).value
let changedGas = hostLoadFrame.info.gas
let changedRegisters = hostLoadFrame.info.registers
assert resumeFlatHostMemory(hostLoadFrame, changedHostMemory, changedGas,
    changedRegisters) == StepError.None
let resumedLoadInfo = hostLoadFrame.info
when defined(pvmArm64Jit):
  let beforePartialLoad = flatArmStatistics(hostLoadFrame)
verifyControl(hostLoadFrame, loadLoop, resumedLoadInfo, 7, [secondWord])
when defined(pvmArm64Jit):
  let partialLoadStats = flatArmStatistics(hostLoadFrame)
  when defined(pvmArm64JitRefuse): assert partialLoadStats[2] == 0
  else:
    # A partial reservation must not enter even a previously published memory leaf.
    assert partialLoadStats[1] == beforePartialLoad[1] and partialLoadStats[2] == beforePartialLoad[2]
# Include the jump and the complete seven-instruction target block, even though its host exit refunds the final jump.
verifyControl(hostLoadFrame, loadLoop, resumedLoadInfo, 8, [secondWord])
assert hostLoadFrame.exit == StepExit.Host and flatHostStats(hostLoadFrame)[1] == 1
assert pageImage(originalHostMemory, PageIndex(16)).value.bytes == firstWord.bytes
when defined(pvmArm64Jit):
  let beforeUnmapping = flatArmStatistics(hostLoadFrame)
  when defined(pvmArm64JitRefuse): assert beforeUnmapping[2] == 0
  else: assert beforeUnmapping[0] > 0 and beforeUnmapping[1] > 0 and beforeUnmapping[2] > 0
  discard observeFlatHostMemory(hostLoadFrame)
  let absentHostMemory = captureMemory([], PageLimit(2)).value
  let unmappedGas = hostLoadFrame.info.gas
  let unmappedRegisters = hostLoadFrame.info.registers
  assert resumeFlatHostMemory(hostLoadFrame, absentHostMemory, unmappedGas,
      unmappedRegisters) == StepError.None
  let unmappedLoadInfo = hostLoadFrame.info
  verifyControl(hostLoadFrame, loadLoop, unmappedLoadInfo, 8)
  assert hostLoadFrame.exit == StepExit.Fault
  let afterUnmapping = flatArmStatistics(hostLoadFrame)
  when defined(pvmArm64JitRefuse): assert afterUnmapping == beforeUnmapping
  else:
    # The stale code sees only the new empty descriptors; its failed guard cannot execute a load or suffix.
    assert afterUnmapping[0] == beforeUnmapping[0] and afterUnmapping[1] == beforeUnmapping[1]+1
    assert afterUnmapping[2] == beforeUnmapping[2] and afterUnmapping[3] == beforeUnmapping[3]

echo "ARM_HEAD_HOST_MAP,1"

var registerBoundaryCases = 0
for pattern in [0'u8, 17, 128, 255]:
  var parts: seq[seq[byte]] = @[]
  for opcode in [136'u8, 137, 142, 143, 213, 214, 215, 216, 217]:
    # Interleave all new comparisons/products so resident results feed later aliases before a partial-prefix exit.
    var part = @[opcode]
    for position in 0..<24: part.add(pattern)
    parts.add(part)
  parts.add(@[0'u8])
  let program = owner(parts)
  let plan = newFlatPlan(program, GasCycleLimit(100000))
  var input = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
  for slot in 0..<13: input.registers[slot] = RegisterValue(high(uint64)-uint64(
      slot)*0x100000001'u64)
  var frame = newFlatFrame(plan, [], input)
  verifyControl(frame, program, input, 100)
  for paid in [false, true]:
    for gas in [0'u64, 1, 8, 9, 10, 1000]:
      for budget in 0'u64..11'u64:
        # Every attempt boundary and exact whole-block price retains the independent single-step CPU/PC/gas result.
        var bounded = input
        bounded.gas = MachineGas(gas)
        bounded.blockCharged = paid
        verifyControl(frame, program, bounded, budget)
        inc registerBoundaryCases
  checkFlatSource(frame)
echo "ARM_REGISTER_BOUNDARIES,", registerBoundaryCases

# Three independently decoded charged shapes form a closed loop; each untaken arm exits through a real panic block.
let regionProgram = owner([@[131'u8, 0, 1], @[88'u8, 0x10, 31, 8, 0, 0, 0], @[0'u8],
  @[151'u8, 0x22, 1], @[152'u8, 0x22, 1], @[173'u8, 0x43, 7, 0, 0, 0], @[0'u8],
  @[200'u8, 0x65, 5], @[139'u8, 0x77, 1], @[82'u8, 0x18, 0, 0xe2, 0xff, 0xff, 0xff], @[0'u8]])
var regionCases = 0
for start in [0'u64, 11, 24]:
  let plan = newFlatPlan(regionProgram, GasCycleLimit(100000))
  var info = MachineInfo(pc: CodeAddress(start), gas: MachineGas(100000), registers: default(RegisterFile))
  info.registers[2] = RegisterValue(high(uint64))
  info.registers[4] = RegisterValue(1)
  info.registers[6] = RegisterValue(0x8000000000000000'u64)
  info.registers[7] = RegisterValue(high(uint64))
  info.registers[8] = RegisterValue(1)
  var frame = newFlatFrame(plan, [], info)
  verifyControl(frame, regionProgram, info, 1000)
  when defined(pvmArm64Jit):
    let connected = flatArmRegionStatistics(frame)
    when defined(pvmArm64JitRefuse): assert connected[0] == 0 and connected[1] == 0
    else: assert connected[0] > 0 and connected[1] > 3
  for paid in [false, true]:
    for gas in [0'u64, 1, 2, 3, 4, 5, 8, 13, 21, 31, 127, 128, 129, 249, 250, 251, 252, 1000, high(uint64)]:
      for budget in [0'u64, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 16, 17, 18, 31, 32, 33,
          63, 64, 65, 127, 128, 129, 249, 250, 251, 252, 1000]:
        # Every guarded block exit retains independent source-attempt/gas precedence, exact PC/paid flags and all registers.
        var bounded = info
        bounded.gas = MachineGas(gas)
        bounded.blockCharged = paid
        verifyControl(frame, regionProgram, bounded, budget)
        inc regionCases
  for exitArm in [0, 1]:
    # Both non-root branch exits publish the resident state before the original panic block executes.
    var outside = info
    if exitArm == 0: outside.registers[4] = RegisterValue(0)
    else: outside.registers[8] = RegisterValue(0)
    verifyControl(frame, regionProgram, outside, 1000)
    inc regionCases
  var cache = takeFlatStream(frame)
  var replacement = info
  replacement.registers[0] = RegisterValue(17)
  replacement.registers[5] = RegisterValue(high(uint64))
  var fresh = newFlatFrame(plan, [], replacement)
  restoreFlatStream(fresh, cache)
  verifyControl(fresh, regionProgram, replacement, 1000)
  when defined(pvmArm64Jit):
    # Code-only ownership transfer must execute against the replacement invocation, never its previous registers or budget.
    let transferred = flatArmRegionStatistics(fresh)
    when defined(pvmArm64JitRefuse): assert transferred[0] == 0
    else: assert transferred[0] > 1
  for policy in [0, 1]:
    # Cached connected code cannot bypass a different complete/lazy pricing owner selected on this same frame.
    let complete = newGasPlan(regionProgram, GasPlanLimits(bytes: GasPlanByteLimit(65536),
        blocks: GasPlanBlockLimit(1024), cycles: GasCycleLimit(100000)))
    assert complete.error == GasPlanError.None
    let lazy = newGasMemo(regionProgram, GasMemoLimits(bytes: GasMemoByteLimit(65536),
        cycles: GasCycleLimit(100000)))
    assert lazy.error == GasMemoError.None
    if policy == 0: assert selectFlatPrices(fresh, complete.value, default(GasMemo)) == StepError.None
    else: assert selectFlatPrices(fresh, default(GasPlan), lazy.value) == StepError.None
    when defined(pvmArm64Jit):
      let before = flatArmRegionStatistics(fresh)
    verifyControl(fresh, regionProgram, info, 1000)
    when defined(pvmArm64Jit): assert flatArmRegionStatistics(fresh) == before
    inc regionCases
  checkFlatSource(fresh)
echo "ARM_REGION_CASES,", regionCases

var controlCases = 0
# Both formerly excluded short suffixes and the accepted four-operation shape retain all boundary checks.
for arithmeticCount in [1, 2, 3, 4]:
  for folded in [false, true]:
    var parts: seq[seq[byte]] = @[]
    if folded: parts.add(@[2'u8])
    for position in 0..<arithmeticCount:
      parts.add(@[149'u8, 0, 1])
      if folded and position == 0: parts.add(@[2'u8])
    let branchPc = uint32(arithmeticCount*3+(if folded: 2 else: 0))
    let backwards = 0'u32-branchPc
    var branch = @[172'u8, 0x10]
    for shift in 0..<4: branch.add(byte((backwards shr (shift*8)) and 255))
    parts.add(branch)
    parts.add(@[0'u8])
    let program = owner(parts)
    let plan = newFlatPlan(program, GasCycleLimit(100000))
    var registers = default(RegisterFile)
    registers[1] = RegisterValue(20)
    let warm = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: registers)
    var frame = newFlatFrame(plan, [], warm)
    verifyControl(frame, program, warm, 100)
    when defined(pvmArm64Jit):
      let counters = flatArmControlStatistics(frame)
      when defined(pvmArm64JitRefuse):
        assert counters[0] == 0 and counters[1] == 0
      else:
        # Normalize the same minimum completed-block evidence: one connected call replaces many scalar entries.
        let connected = flatArmRegionStatistics(frame)
        assert connected[0] <= counters[0] and connected[0] <= counters[1]
        assert connected[1] >= connected[0] and connected[1] <= 100
        let internalBlocks = connected[1]-connected[0]
        assert counters[0]+internalBlocks >= 4 and counters[1]+internalBlocks >= 3

    for paid in [false, true]:
      for gas in [0'u64, 1, 4, 5, 6, 9, 10, 25, 26, 27, 1000, high(uint64)]:
        for budget in 0'u64..40'u64:
          let input = MachineInfo(pc: CodeAddress(0), gas: MachineGas(gas), registers: registers,
              blockCharged: paid)
          verifyControl(frame, program, input, budget)
          inc controlCases
    for policy in [0, 1]:
      # Explicit complete/lazy price owners must preserve the same native charge/quota observations as dynamic pricing.
      var priced = newFlatFrame(plan, [], warm)
      let complete = newGasPlan(program, GasPlanLimits(bytes: GasPlanByteLimit(65536),
          blocks: GasPlanBlockLimit(1024), cycles: GasCycleLimit(100000)))
      assert complete.error == GasPlanError.None
      let lazy = newGasMemo(program, GasMemoLimits(bytes: GasMemoByteLimit(65536),
          cycles: GasCycleLimit(100000)))
      assert lazy.error == GasMemoError.None
      if policy == 0:
        assert selectFlatPrices(priced, complete.value, default(GasMemo)) == StepError.None
      else:
        assert selectFlatPrices(priced, default(GasPlan), lazy.value) == StepError.None
        assert gasMemoInfo(lazy.value).value.pricedBlocks == 0
        verifyControl(priced, program, warm, 0)
        assert gasMemoInfo(lazy.value).value.pricedBlocks == 0
        verifyControl(priced, program, warm, 1)
        assert gasMemoInfo(lazy.value).value.pricedBlocks == 1
      verifyControl(priced, program, warm, 100)
      when defined(pvmArm64Jit):
        let observed = flatArmControlStatistics(priced)
        when defined(pvmArm64JitRefuse):
          assert observed[0] == 0 and observed[1] == 0
        else:
          assert observed[0] >= 4 and observed[1] >= 3
      for paid in [false, true]:
        for gas in [0'u64, 1, 6, 7, 8, 35, 1000]:
          for budget in [0'u64, 1, 4, 5, 6, 7, 8, 34, 35, 36, 37, 100]:
            let input = MachineInfo(pc: CodeAddress(0), gas: MachineGas(gas), registers: registers,
                blockCharged: paid)
            verifyControl(priced, program, input, budget)
            inc controlCases
      if policy == 1: assert gasMemoInfo(lazy.value).value.pricedBlocks == 2
    # Transfer retains promoted headers and leaves with their exact plan; a new frame owns fresh CPU and budgets.
    var transferred = takeFlatStream(frame)
    var fresh = newFlatFrame(plan, [], warm)
    restoreFlatStream(fresh, transferred)
    verifyControl(fresh, program, warm, 100)
    when defined(pvmArm64Jit):
      let retired = flatArmControlStatistics(fresh)
      when defined(pvmArm64JitRefuse):
        assert retired[0] == 0 and retired[1] == 0
      else:
        assert retired[0] >= 9 and retired[1] >= 7
      assert flatArmControlStatistics(frame) == default(array[2, uint64])

echo "ARM_CONTROL_CASES,", controlCases

var pairControlCases = 0
for boundary in 0..<3:
  # Both branch successors are genuine admitted headers; the first target equals fallthrough, the second closes the loop.
  var parts = @[@[149'u8, 0, 1], @[172'u8, 0x10, 6, 0, 0, 0],
      @[149'u8, 0, 1], @[172'u8, 0x10, 0xf4, 0xff, 0xff, 0xff]]
  if boundary == 1:
    # The external edge must preserve ordered host suspension at its original source PC.
    parts.add(@[10'u8, 7])
  elif boundary == 2:
    # An unmapped load remains checked after the connected loop, with exact fault/paid/prefix observations.
    parts.add(@[52'u8, 2, 1, 0, 1, 0])
  parts.add(@[0'u8])
  let pairProgram = owner(parts)
  let pairPlan = newFlatPlan(pairProgram, GasCycleLimit(100000))
  var pairRegisters = default(RegisterFile)
  pairRegisters[1] = RegisterValue(20)
  let pairWarm = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: pairRegisters)
  var pairFrame = newFlatFrame(pairPlan, [], pairWarm)
  verifyControl(pairFrame, pairProgram, pairWarm, 100)
  when defined(pvmArm64Jit):
    let connected = flatArmRegionStatistics(pairFrame)
    when defined(pvmArm64JitRefuse): assert connected == default(array[2, uint64])
    else: assert connected[0] > 0 and connected[1] > connected[0]
  for entry in [0'u64, 9'u64]:
    for paid in [false, true]:
      for gas in [0'u64, 1, 2, 3, 4, 5, 39, 40, 41, 42, 1000, high(uint64)]:
        for budget in 0'u64..44'u64:
          # Every attempted prefix, paid state, gas edge, entry rotation and external exit matches checked single stepping.
          let input = MachineInfo(pc: CodeAddress(entry), gas: MachineGas(gas),
              registers: pairRegisters, blockCharged: paid)
          verifyControl(pairFrame, pairProgram, input, budget)
          inc pairControlCases
  var pairCache = takeFlatStream(pairFrame)
  var freshPair = newFlatFrame(pairPlan, [], pairWarm)
  restoreFlatStream(freshPair, pairCache)
  when defined(pvmArm64Jit):
    let before = flatArmRegionStatistics(freshPair)
  verifyControl(freshPair, pairProgram, pairWarm, 100)
  when defined(pvmArm64Jit):
    when defined(pvmArm64JitRefuse): assert flatArmRegionStatistics(freshPair) == before
    else: assert flatArmRegionStatistics(freshPair)[0] > before[0]
  for policy in [0, 1]:
    # A retained connected image never bypasses an explicitly selected complete or lazy price owner.
    let complete = newGasPlan(pairProgram, GasPlanLimits(bytes: GasPlanByteLimit(65536),
        blocks: GasPlanBlockLimit(1024), cycles: GasCycleLimit(100000)))
    let lazy = newGasMemo(pairProgram, GasMemoLimits(bytes: GasMemoByteLimit(65536),
        cycles: GasCycleLimit(100000)))
    assert complete.error == GasPlanError.None and lazy.error == GasMemoError.None
    if policy == 0: assert selectFlatPrices(freshPair, complete.value, default(GasMemo)) == StepError.None
    else: assert selectFlatPrices(freshPair, default(GasPlan), lazy.value) == StepError.None
    when defined(pvmArm64Jit):
      let beforePolicy = flatArmRegionStatistics(freshPair)
    verifyControl(freshPair, pairProgram, pairWarm, 100)
    when defined(pvmArm64Jit): assert flatArmRegionStatistics(freshPair) == beforePolicy
    inc pairControlCases
echo "ARM_TWO_BLOCK_CONTROL_CASES,", pairControlCases

var boundaryCases = 0
for boundary in [0, 1]:
  var parts = @[@[149'u8, 0, 1], @[149'u8, 0, 1], @[149'u8, 0, 1], @[149'u8, 0, 1],
      @[172'u8, 0x10, 0xf4, 0xff, 0xff, 0xff]]
  if boundary == 0:
    # Native false continuation must arrive at the genuine checked ECALL with its exact source PC and identifier.
    parts.add(@[10'u8, 7])
  else:
    # An unmapped load must retain whole-block gas, exact page/PC and refund the unattempted trap reservation.
    parts.add(@[52'u8, 2, 1, 0, 1, 0])
  parts.add(@[0'u8])
  let program = owner(parts)
  var registers = default(RegisterFile)
  registers[1] = RegisterValue(20)
  let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: registers)
  var frame = newFlatFrame(newFlatPlan(program, GasCycleLimit(100000)), [], initial)
  verifyControl(frame, program, initial, 100)
  assert frame.exit == (if boundary == 0: StepExit.Host else: StepExit.Fault)
  when defined(pvmArm64Jit):
    let counters = flatArmControlStatistics(frame)
    when defined(pvmArm64JitRefuse):
      assert counters[0] == 0 and counters[1] == 0
    else:
      # The approved completed-block normalization also applies before genuine host/fault exits; all state checks remain exact.
      let connected = flatArmRegionStatistics(frame)
      assert connected[0] <= counters[0] and connected[0] <= counters[1]
      assert connected[1] >= connected[0] and connected[1] <= 100
      let internalBlocks = connected[1]-connected[0]
      assert counters[0]+internalBlocks >= 4 and counters[1]+internalBlocks >= 3
  for gas in [0'u64, 1, 24, 25, 26, 27, 1000]:
    for budget in 0'u64..30'u64:
      let input = MachineInfo(pc: CodeAddress(0), gas: MachineGas(gas), registers: registers)
      verifyControl(frame, program, input, budget)
      inc boundaryCases
echo "ARM_HOST_FAULT_CASES,", boundaryCases

# A genuine host mapping replacement takes the slow reentry path without losing its live code capability.
let mappingProgram = owner([@[149'u8, 0, 1], @[149'u8, 0, 1], @[149'u8, 0, 1],
  @[149'u8, 0, 1], @[10'u8, 7], @[0'u8]])
var mappingFrame = newFlatFrame(newFlatPlan(mappingProgram, GasCycleLimit(100000)), [], initial)
runFlat(mappingFrame, 100)
assert mappingFrame.reason == StepError.None and mappingFrame.exit == StepExit.Host
let suspended = observeFlatHostMemory(mappingFrame)
var mapped = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly,
  bytes: default(array[4096, byte]))
mapped.bytes[17] = 123
let posterior = captureMemory([mapped], PageLimit(2))
assert posterior.error == MachineError.None
let resumedGas = mappingFrame.info.gas
let resumedRegisters = mappingFrame.info.registers
assert resumeFlatHostMemory(mappingFrame, posterior.value, resumedGas,
  resumedRegisters) == StepError.None
assert flatHostStats(mappingFrame)[1] == 1
runFlat(mappingFrame, 100)
assert mappingFrame.reason == StepError.None and mappingFrame.exit == StepExit.Panic
let published = flatMemorySnapshot(mappingFrame)
assert pageImage(published, mapped.index).value.bytes == mapped.bytes
assert memoryPageCount(suspended).value == PageCount(0)
resetFlatFrame(mappingFrame, initial)
runFlat(mappingFrame, 100)
assert mappingFrame.reason == StepError.None and mappingFrame.exit == StepExit.Host
when defined(pvmArm64Jit):
  let kept = flatArmStatistics(mappingFrame)
  when defined(pvmArm64JitRefuse):
    assert kept[0] == 0 and kept[1] == 0
  else:
    assert kept[0] == 1 and kept[1] == 2 and kept[2] == 8
echo "ARM_MAPPING_REENTRY,1"


# One pure block previously returned through ordinary dispatch on every trip despite resident-region support.
let selfRegionProgram = owner([@[131'u8, 0, 1], @[88'u8, 0x10, 31, 0xfd, 0xff, 0xff, 0xff], @[0'u8]])
let selfRegionPlan = newFlatPlan(selfRegionProgram, GasCycleLimit(100000))
var selfInfo = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
var selfRegion = newFlatFrame(selfRegionPlan, [], selfInfo)
for visit in 0..<3:
  # The existing independent source-step oracle checks both cold discovery and actual reused connected execution.
  verifyControl(selfRegion, selfRegionProgram, selfInfo, 1000)
when defined(pvmArm64Jit):
  let observed = flatArmRegionStatistics(selfRegion)
  when defined(pvmArm64JitRefuse): assert observed == default(array[2, uint64])
  else: assert observed[0] > 0 and observed[1] > observed[0]
var selfRegionCases = 0
for paid in [false, true]:
  for initial in [0'u64, 30, 31, 32]:
    for gas in [0'u64, 1, 2, 3, 4, 5, 63, 64, 65, high(uint64)]:
      for budget in [0'u64, 1, 2, 3, 4, 5, 63, 64, 65, 127, 128, 129]:
        # Every native guard retains exact source/gas/paid-state ordering, including a branch that leaves immediately.
        var bounded = selfInfo
        bounded.registers[0] = RegisterValue(initial)
        bounded.gas = MachineGas(gas)
        bounded.blockCharged = paid
        verifyControl(selfRegion, selfRegionProgram, bounded, budget)
        inc selfRegionCases
echo "ARM_SELF_REGION_CASES,", selfRegionCases
