# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Local JIT alias/overflow and reservation witness against the engine's bounded single-step adapter.
import std/[assertions, syncio]
import ../../src/codec/natural
import ../../src/pvm/[program, machine]
import ../../src/pvm/gas/gas
import ../../src/pvm/[step, registers]
import ../../src/pvm/gas/[plan as gas_plan, memo as gas_memo]
when defined(pvmArm64Jit):
  import ../../src/pvm/internal/arm64_jit
  import ../support/pvm_arm_memory_cycle_backend
import ../../src/pvm/internal/handler_stream

when defined(pvmArm64Jit):
  proc checkRegionCharges(jit: ArmJit, headers, spans: array[3, uint32],
      prices: array[3, uint64]): int =
    ## Compare scalar checks to the retained complete matcher for each genuine and individually corrupted record.
    result = 0
    assert armRegionMatches(jit, headers, spans, prices)
    for index in 0..<3:
      # All fields of active and sentinel records must match before independent mutation controls run.
      let coordinate = range[0..2](index)
      assert armRegionChargeMatches(jit, coordinate, headers[index], spans[index], prices[index])
      inc result
      for field in 0..<3:
        var alteredHeaders = headers
        var alteredSpans = spans
        var alteredPrices = prices
        case field
        of 0: alteredHeaders[index] = alteredHeaders[index] xor 1'u32 # Only the captured source header changes.
        of 1: alteredSpans[index] = alteredSpans[index] xor 1'u32 # Only the complete source span changes.
        else: alteredPrices[index] = alteredPrices[index] xor 1'u64 # Preserve all other full-width pricing bits.
        let complete = armRegionMatches(jit, alteredHeaders, alteredSpans, alteredPrices)
        assert not complete
        let scalar = armRegionChargeMatches(jit, coordinate, alteredHeaders[index],
          alteredSpans[index], alteredPrices[index])
        assert scalar == complete
        inc result

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
  var widthLiteralCases = 0
  when not defined(pvmArm64JitRefuse):
    for opcode in 124'u8..130'u8:
      let readOpcode = int(opcode)
      assert readOpcode >= 124 and readOpcode <= 130 # The literal loop supplies the same closed width domain.
      let width = case opcode
        of 124, 125: 1
        of 126, 127: 2
        of 128, 129: 4
        else: 8
      for destination in 0..<13:
        for addressSlot in 0..<13:
          let fixture = owner([@[opcode, byte(addressSlot*16+destination), 0, 0, 0, 0], @[0'u8]])
          let slots = instructionRegisters(instruction(fixture, CodeAddress(0)))
          let jit = newArmJit()
          assert armEntry(jit, 0, 1) == 0
          var suffix = default(ArmBlock)
          var words = armMemoryInstructions(suffix, slots, 0, 37, range[124..130](readOpcode))
          assert publishArmEntry(jit, 0, 37, 1, words)
          var bytes = default(array[16, byte])
          for value in [0'u64, 0x80'u64, 0x8000'u64, 0x80000000'u64, 0x8000000000000000'u64,
              high(uint64), 0x0123456789abcdef'u64]:
            for at in 0..<8: bytes[3+at] = byte((value shr (at*8)) and 255)
            var literal = 0'u64
            for at in 0..<width: literal = literal or (uint64(bytes[3+at]) shl (at*8))
            if opcode in [125'u8, 127, 129] and (bytes[3+width-1] and 128) != 0:
              # Independent byte assembly and an explicit high-bit fill model complete sign extension.
              literal = literal or (high(uint64) shl (width*8))
            for region in 0..<3:
              var descriptors = default(array[3, array[3, uint64]])
              descriptors[region] = [65536'u64, 9'u64, cast[uint64](addr bytes[0])]
              var registers = default(RegisterFile)
              for slot in 0..<13: registers[slot] = RegisterValue(0x923456789abcdef0'u64+uint64(slot))
              registers[addressSlot] = RegisterValue(0x100010003'u64)
              var expected = registers
              expected[destination] = RegisterValue(literal)
              assert callArmMemory(jit, 0, registers, descriptors) == 37
              assert registers == expected
              inc widthLiteralCases
  echo "ARM_LOAD_WIDTH_LITERAL_CASES,", widthLiteralCases
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
  var directBranchLiteralCases = 0
  when not defined(pvmArm64JitRefuse):
    for opcode in 52'u8..58'u8:
      let readOpcode = int(opcode)
      let width = 1 shl ((readOpcode-52) div 2)
      for destination in 0..<13:
        let other = (destination+1) mod 13
        let fixture = owner([@[opcode, byte(destination), 3, 0, 1, 0],
          @[149'u8, byte(destination*16+destination), 1],
          @[170'u8, byte(other*16+destination), 0, 0, 0, 0], @[0'u8]])
        var span = default(ArmReadSpan)
        emitArmDirectRead(span, instructionRegisters(instruction(fixture, CodeAddress(0))),
            65539, range[52..58](readOpcode))
        emitArmReadArithmetic(span, 149,
            instructionRegisters(instruction(fixture, CodeAddress(6))), 1)
        emitArmReadBranch(span, 170,
            instructionRegisters(instruction(fixture, CodeAddress(9))), 0, 7, 9)
        let jit = newArmJit()
        assert armEntry(jit, 0, 1) == 0
        var words = armReadInstructions(span, 2, true)
        assert publishArmEntry(jit, 0, 2, 3, words)
        var bytes = default(array[16, byte])
        for at in 0..<width: bytes[3+at] = byte(at*23+17)
        if opcode in [53'u8, 55, 57]: bytes[3+width-1] = 0x80
        var value = 0'u64
        for at in 0..<width: value = value or (uint64(bytes[3+at]) shl (8*at))
        if opcode in [53'u8, 55, 57] and (bytes[3+width-1] and 128) != 0:
          value = value or (high(uint64) shl (width*8))
        let advanced = RegisterValue(value+1)
        for region in 0..<3:
          for selected in [false, true]:
            for layout in 0..<3:
              # The immediate never reads a guest base; refusal must leave the destination and branch operands untouched.
              var descriptors = default(array[3, array[3, uint64]])
              if layout != 1:
                descriptors[region] = [65536'u64, (if layout == 2: 3'u64 else: 9'u64),
                    cast[uint64](addr bytes[0])]
              var registers = default(RegisterFile)
              for slot in 0..<13: registers[slot] = RegisterValue(0x1122334455667788'u64+uint64(slot))
              registers[other] = RegisterValue(uint64(advanced)+(if selected: 0'u64 else: 1'u64))
              let original = registers
              let before = jit.operations
              let next = callArmMemoryBranch(jit, 0, 7, 9, registers, descriptors)
              if layout == 0:
                assert next == (if selected: 7'u32 else: 9'u32)
                var expected = original
                expected[destination] = advanced
                assert registers == expected and jit.operations == before+3
              else:
                assert next == high(uint32) and registers == original and jit.operations == before
              inc directBranchLiteralCases
    for address in [65535'u32, 0xfffffff8'u32]:
      let fixture = owner([@[58'u8, 0, 0, 0, 0, 0], @[149'u8, 0, 1],
        @[170'u8, 0x10, 0, 0, 0, 0], @[0'u8]])
      var span = default(ArmReadSpan)
      emitArmDirectRead(span, instructionRegisters(instruction(fixture, CodeAddress(0))),
          address, 58)
      emitArmReadArithmetic(span, 149,
          instructionRegisters(instruction(fixture, CodeAddress(6))), 1)
      emitArmReadBranch(span, 170,
          instructionRegisters(instruction(fixture, CodeAddress(9))), 0, 7, 9)
      let jit = newArmJit()
      assert armEntry(jit, 0, 1) == 0
      var words = armReadInstructions(span, 2, true)
      assert publishArmEntry(jit, 0, 2, 3, words)
      var bytes = default(array[16, byte])
      var descriptors = default(array[3, array[3, uint64]])
      descriptors[0] = [uint64(address), 9'u64, cast[uint64](addr bytes[0])]
      var registers = default(RegisterFile)
      registers[0] = RegisterValue(123)
      let original = registers
      assert callArmMemoryBranch(jit, 0, 7, 9, registers, descriptors) == high(uint32)
      assert registers == original
      inc directBranchLiteralCases
  echo "ARM_DIRECT_BRANCH_LITERAL_CASES,", directBranchLiteralCases
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
          checkFlatSource(frame, [])
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
checkFlatSource(second, [])
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
    var scalarMatchCases = 0
    let unpublished = newArmJit()
    for index in 0..<3:
      # Unpublished metadata must refuse even a default-looking record.
      assert not armRegionChargeMatches(unpublished, range[0..2](index), 0, 0, 0)
      inc scalarMatchCases
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
    scalarMatchCases += checkRegionCharges(bounded, [0'u32, 1, 2], [2'u32, 2, 2], [1'u64, 1, 1])
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
        let firstPhase = if rotated: 1 else: 0
        let secondPhase = 1-firstPhase
        scalarMatchCases += checkRegionCharges(pairJit,
          [pairBlocks[0].header, pairBlocks[1].header, high(uint32)], [2'u32, 2, 0],
          [prices[firstPhase], prices[secondPhase], 0'u64])
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
    echo "ARM_REGION_SCALAR_MATCH_CASES,", scalarMatchCases

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
  for slot in 0..<13:
    if frame.info.registers[slot] != wanted.registers[slot]:
      echo "CONTROL_REGISTER,", slot, ",", uint64(frame.info.registers[slot]), ",", uint64(
          wanted.registers[slot]), ",", budget
    assert frame.info.registers[slot] == wanted.registers[slot]
  checkFlatSource(frame, images)
  if images.len != 0:
    # The independent single-step machine owns expected store effects; every original input snapshot stays immutable.
    let published = flatMemorySnapshot(frame)
    let expectedMemory = memoryOf(expected)
    assert expectedMemory.error == MachineError.None
    for image in images:
      let actual = pageImage(published, image.index)
      let wantedPage = pageImage(expectedMemory.value, image.index)
      let original = pageImage(memory, image.index)
      assert actual.error == MachineError.None and wantedPage.error == MachineError.None
      assert original.error == MachineError.None
      assert actual.value.access == wantedPage.value.access and actual.value.bytes ==
          wantedPage.value.bytes
      assert original.value.access == image.access and original.value.bytes == image.bytes

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
            if layout == 0: assert stats[2] == 0
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
for secondOpcode in 124'u8..130'u8:
  for layout in 0..<8:
    let base = if layout == 7: 0xfffff000'u64 else: 65536'u64
    for aliased in [false, true]:
      let first = if aliased: 1 else: 0
      let last = if aliased: 2 else: 3
      let program = owner([@[130'u8, byte(0x10+first), 0, 0, 0, 0],
        @[149'u8, byte(first*16+2), 9], @[secondOpcode, byte(0x20+last), 0, 0, 0, 0],
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
  checkFlatSource(frame, [])
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
    # Select pricing before emission, then prove a default-priced connected stream is discarded on restore.
    let complete = newGasPlan(regionProgram, GasPlanLimits(bytes: GasPlanByteLimit(65536),
        blocks: GasPlanBlockLimit(1024), cycles: GasCycleLimit(100000)))
    assert complete.error == GasPlanError.None
    let lazy = newGasMemo(regionProgram, GasMemoLimits(bytes: GasMemoByteLimit(65536),
        cycles: GasCycleLimit(100000)))
    assert lazy.error == GasMemoError.None
    let unchangedInfo = fresh.info
    let unchangedRemaining = fresh.remaining
    when defined(pvmArm64Jit):
      let unchangedNative = flatArmStatistics(fresh)
      let unchangedRegion = flatArmRegionStatistics(fresh)
    if policy == 0:
      assert selectFlatPrices(fresh, complete.value, default(GasMemo)) ==
          StepError.InvalidPreparedProgram
    else:
      assert selectFlatPrices(fresh, default(GasPlan), lazy.value) ==
          StepError.InvalidPreparedProgram
    assert fresh.info.pc == unchangedInfo.pc and fresh.info.gas == unchangedInfo.gas and
        fresh.info.blockCharged == unchangedInfo.blockCharged and
        fresh.info.registers == unchangedInfo.registers and fresh.remaining == unchangedRemaining
    when defined(pvmArm64Jit):
      assert flatArmStatistics(fresh) == unchangedNative and
          flatArmRegionStatistics(fresh) == unchangedRegion
    var source = newFlatFrame(plan, [], info)
    verifyControl(source, regionProgram, info, 1000)
    var pricedStream = takeFlatStream(source)
    assert streamNodes(pricedStream) > 0
    var priced = newFlatFrame(plan, [], info)
    if policy == 0: assert selectFlatPrices(priced, complete.value, default(GasMemo)) == StepError.None
    else: assert selectFlatPrices(priced, default(GasPlan), lazy.value) == StepError.None
    restoreFlatStream(priced, pricedStream)
    assert streamNodes(pricedStream) == 0
    var discarded = takeFlatStream(priced)
    assert streamNodes(discarded) == 0
    when defined(pvmArm64Jit):
      let before = flatArmRegionStatistics(priced)
    verifyControl(priced, regionProgram, info, 1000)
    when defined(pvmArm64Jit): assert flatArmRegionStatistics(priced) == before
    inc regionCases
  checkFlatSource(fresh, [])
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
    # A fresh policy owner discards a default-priced connected image before any handler is emitted.
    let complete = newGasPlan(pairProgram, GasPlanLimits(bytes: GasPlanByteLimit(65536),
        blocks: GasPlanBlockLimit(1024), cycles: GasCycleLimit(100000)))
    let lazy = newGasMemo(pairProgram, GasMemoLimits(bytes: GasMemoByteLimit(65536),
        cycles: GasCycleLimit(100000)))
    assert complete.error == GasPlanError.None and lazy.error == GasMemoError.None
    var source = newFlatFrame(pairPlan, [], pairWarm)
    verifyControl(source, pairProgram, pairWarm, 100)
    var pricedStream = takeFlatStream(source)
    assert streamNodes(pricedStream) > 0
    var priced = newFlatFrame(pairPlan, [], pairWarm)
    if policy == 0: assert selectFlatPrices(priced, complete.value, default(GasMemo)) == StepError.None
    else: assert selectFlatPrices(priced, default(GasPlan), lazy.value) == StepError.None
    restoreFlatStream(priced, pricedStream)
    assert streamNodes(pricedStream) == 0
    var discarded = takeFlatStream(priced)
    assert streamNodes(discarded) == 0
    when defined(pvmArm64Jit):
      let beforePolicy = flatArmRegionStatistics(priced)
    verifyControl(priced, pairProgram, pairWarm, 100)
    when defined(pvmArm64Jit): assert flatArmRegionStatistics(priced) == beforePolicy
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

# A direct signed read, pure update and cached branch retain the original charged loop boundary.
let directLoopProgram = owner([@[57'u8, 0, 0, 0, 1, 0],
    @[149'u8, 0x11, 1], @[171'u8, 0x21, 0xf7, 0xff, 0xff, 0xff], @[0'u8]])
let directLoopPlan = newFlatPlan(directLoopProgram, GasCycleLimit(100000))
var directLoopPage = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly)
directLoopPage.bytes[3] = 0x80
var directLoopRegisters = default(RegisterFile)
directLoopRegisters[2] = RegisterValue(4)
let directLoopInfo = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000),
    registers: directLoopRegisters)
var directLoopFrame = newFlatFrame(directLoopPlan, [directLoopPage], directLoopInfo)
for warm in 0..<2:
  verifyControl(directLoopFrame, directLoopProgram, directLoopInfo, 100, [directLoopPage])
when defined(pvmArm64Jit):
  when defined(pvmArm64JitRefuse):
    assert flatArmControlStatistics(directLoopFrame) == default(array[2, uint64])
  else:
    let control = flatArmControlStatistics(directLoopFrame)
    let directStats = flatArmStatistics(directLoopFrame)
    # This isolated program has exactly one three-operation composite candidate. The older
    # checked-load plus two-operation native branch would increment calls without this ratio.
    assert directStats[1] > 0 and directStats[2] == 3*directStats[1] and
        control[0] == directStats[1],
        "direct read and conditional must execute in the same native fragment"
else:
  echo "ARM_DIRECT_BRANCH_LITERAL_CASES,0"
var directLoopControlCases = 0
for paid in [false, true]:
  for gas in [0'u64, 1, 2, 1000]:
    for budget in 0'u64..14'u64:
      # Warm native code must retain partial reservation, paid reentry and gas refusal precedence.
      var input = directLoopInfo
      input.gas = MachineGas(gas)
      input.blockCharged = paid
      verifyControl(directLoopFrame, directLoopProgram, input, budget, [directLoopPage])
      inc directLoopControlCases
for layout in 0..<2:
  let images = if layout == 0: @[directLoopPage] else: newSeq[PageImage]()
  assert replaceFlatMemoryChecked(directLoopFrame, images, directLoopInfo) == FlatError.None
  verifyControl(directLoopFrame, directLoopProgram, directLoopInfo, 100, images)
  inc directLoopControlCases
echo "ARM_DIRECT_BRANCH_CONTROL_CASES,", directLoopControlCases

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


# Rejected single-block admission must preserve both ordinary and specialized checked loop behavior.
var selfRegionCases = 0
for specialized in [false, true]:
  let source = if specialized:
      owner([@[131'u8, 0, 1], @[88'u8, 0x10, 31, 0xfd, 0xff, 0xff, 0xff], @[0'u8]])
    else:
      owner([@[149'u8, 0, 1], @[172'u8, 0x10, 0xfd, 0xff, 0xff, 0xff], @[0'u8]])
  let plan = newFlatPlan(source, GasCycleLimit(100000))
  var warm = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
  warm.registers[1] = RegisterValue(32)
  var frame = newFlatFrame(plan, [], warm)
  for visit in 0..<3:
    # The source-step oracle checks cold and reused fallback execution without using the region's own results.
    verifyControl(frame, source, warm, 1000)
  when defined(pvmArm64Jit):
    # The measured self-loop admission was rejected: neither one-block shape may steal the accepted multi-block region slot.
    assert flatArmRegionStatistics(frame) == default(array[2, uint64])
  for paid in [false, true]:
    for initial in [0'u64, 30, 31, 32]:
      for gas in [0'u64, 1, 2, 3, 4, 5, 63, 64, 65, high(uint64)]:
        for budget in [0'u64, 1, 2, 3, 4, 5, 63, 64, 65, 127, 128, 129]:
          # Both paths retain exact gas, source-prefix and paid-state ordering, including immediately untaken loops.
          var bounded = warm
          bounded.registers[0] = RegisterValue(initial)
          bounded.gas = MachineGas(gas)
          bounded.blockCharged = paid
          verifyControl(frame, source, bounded, budget)
          inc selfRegionCases
echo "ARM_SELF_REGION_CASES,", selfRegionCases


var storeControls = 0
for layout in 0..<8:
  let base = if layout == 5: 0xfffff000'u64 elif layout == 6: 0x40000'u64
    elif layout == 7: 0x3f000'u64 else: 65536'u64
  var images: seq[PageImage] = @[]
  if layout != 0:
    # Fragmented, protected and read-only layouts must preserve canonical faults or take the exact checked fallback.
    var image = PageImage(index: PageIndex(uint32(base shr 12)),
      access: (if layout == 2: PageAccess.ReadOnly elif layout == 4: PageAccess.Inaccessible
      else: PageAccess.ReadWrite), bytes: default(array[4096, byte]))
    if image.access != PageAccess.Inaccessible:
      for index in 0..<4096: image.bytes[index] = byte((index*17+layout) mod 256)
    images.add(image)
    if layout == 3:
      var extra = image
      extra.index = PageIndex(20)
      images.add(extra)
  for placement in 0..<4:
    for hosted in [false, true]:
      var parts: seq[seq[byte]] = @[]
      for index in 0..<placement: parts.add(@[149'u8, 0, 1])
      parts.add(@[120'u8, 0x10, 0])
      for index in placement..<3: parts.add(@[149'u8, 0, 1])
      if hosted: parts.add(@[10'u8, 7])
      parts.add(@[0'u8])
      let program = owner(parts)
      for address in [0'u64, 65535, base, base+4095, base+4096, 0xffffffff'u64,
          base+17+0x100000000'u64]:
        let plan = newFlatPlan(program, GasCycleLimit(100000))
        var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
        info.registers[0] = RegisterValue(0x123456789abcdef0'u64)
        info.registers[1] = RegisterValue(address)
        var frame = newFlatFrame(plan, images, info)
        verifyControl(frame, program, info, 100, images)
        for paid in [false, true]:
          for gas in [0'u64, 1, 3, 4, 5, 1000]:
            for budget in 0'u64..7'u64:
              # Every source attempt, initial paid state and gas prefix matches the independent one-step engine.
              var input = info
              input.gas = MachineGas(gas)
              input.blockCharged = paid
              verifyControl(frame, program, input, budget, images)
              inc storeControls
        var cache = takeFlatStream(frame)
        var fresh = newFlatFrame(plan, images, info)
        restoreFlatStream(fresh, cache)
        verifyControl(fresh, program, info, 100, images)
        assert replaceFlatMemoryChecked(fresh, [], info) == FlatError.None
        verifyControl(fresh, program, info, 100)
        storeControls+=2
echo "ARM_STORE_FALLBACK_CONTROL_CASES,", storeControls

let checkedTailProgram = owner([@[149'u8, 0x22, 1], @[120'u8, 0x02, 0],
    @[149'u8, 0x33, 1], @[149'u8, 0x44, 1], @[172'u8, 0x12, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
let checkedTailPlan = newFlatPlan(checkedTailProgram, GasCycleLimit(100000))
let checkedTailPage = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))
var checkedTailRegisters = default(RegisterFile)
checkedTailRegisters[0] = RegisterValue(65536)
checkedTailRegisters[1] = RegisterValue(20)
let checkedTailInfo = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000),
    registers: checkedTailRegisters)
var checkedTailFrame = newFlatFrame(checkedTailPlan, [checkedTailPage], checkedTailInfo)
verifyControl(checkedTailFrame, checkedTailProgram, checkedTailInfo, 120, [checkedTailPage])
# The second invocation also exercises the same retained stream after native promotion.
verifyControl(checkedTailFrame, checkedTailProgram, checkedTailInfo, 120, [checkedTailPage])
when defined(pvmArm64Jit):
  when defined(pvmArm64JitRefuse):
    assert flatArmControlStatistics(checkedTailFrame)[0] == 0
  else:
    # The suffix must be positively promoted before testing the cached checked-prefix handoff.
    assert flatArmControlStatistics(checkedTailFrame)[0] > 0
var checkedTailCases = 0
for layout in 0..<3:
  var pages: seq[PageImage] = @[]
  if layout != 2:
    var page = checkedTailPage
    if layout == 1: page.access = PageAccess.ReadOnly
    pages.add(page)
  assert replaceFlatMemoryChecked(checkedTailFrame, pages, checkedTailInfo) == FlatError.None
  for paid in [false, true]:
    for gas in [0'u64, 1, 4, 5, 1000]:
      for budget in [0'u64, 1, 2, 3, 4, 5, 6, 7, 8, 99, 100, 101]:
        # Retained native code must preserve store effects, faults, paid state and every partial reservation.
        var input = checkedTailInfo
        input.gas = MachineGas(gas)
        input.blockCharged = paid
        verifyControl(checkedTailFrame, checkedTailProgram, input, budget, pages)
        inc checkedTailCases
echo "ARM_CHECKED_TAIL_CONTROL_CASES,", checkedTailCases

# Copy the rising r1 value through the prefix into store r2; the published bytes must vary.
let dirtyLoopProgram = owner([@[198'u8, 0x41, 2], @[120'u8, 0x02, 0],
    @[149'u8, 0x00, 1], @[149'u8, 0x11, 1],
    @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
let dirtyLoopPlan = newFlatPlan(dirtyLoopProgram, GasCycleLimit(100000))
let dirtyLoopPage = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))
var dirtyLoopRegisters = default(RegisterFile)
dirtyLoopRegisters[0] = RegisterValue(65536)
dirtyLoopRegisters[1] = RegisterValue(0x1234)
dirtyLoopRegisters[2] = RegisterValue(0xa5) # Poison the store value until the prefix publishes each new byte.
dirtyLoopRegisters[3] = RegisterValue(65552)
let dirtyLoopInfo = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000),
    registers: dirtyLoopRegisters)
var dirtyLoopFrame = newFlatFrame(dirtyLoopPlan, [dirtyLoopPage], dirtyLoopInfo)
for warm in 0..<6:
  verifyControl(dirtyLoopFrame, dirtyLoopProgram, dirtyLoopInfo, 100, [dirtyLoopPage])
let warmMemory = pageImage(flatMemorySnapshot(dirtyLoopFrame), PageIndex(16))
assert warmMemory.error == MachineError.None
assert warmMemory.value.bytes[0] == 0x34 and warmMemory.value.bytes[1] == 0x35 and
    warmMemory.value.bytes[15] == 0x43
when defined(pvmArm64Jit):
  let native = flatArmDirtyLoopStatistics(dirtyLoopFrame)
  when defined(pvmArm64JitRefuse):
    assert native == default(array[3, uint64])
  else:
    assert native[0] > 0 and native[1] > native[0] and native[2] > 0
    echo "ARM_DIRTY_LOOP,", native[0], ",", native[1], ",", native[2]
# Independent store-only inputs must survive masked native entry, including the highest guest slot.
var dirtyLiveInCases = 0
for valueSlot in [6'u8, 12'u8]:
  let program = owner([@[198'u8, 0x41, 2], @[120'u8, valueSlot, 0],
      @[149'u8, 0x00, 1], @[149'u8, 0x11, 1],
      @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
  let plan = newFlatPlan(program, GasCycleLimit(100000))
  var registers = default(RegisterFile)
  for slot in 0..<13:
    # Distinct high-bit sentinels expose unintended writes and missing original register loads.
    registers[slot] = RegisterValue(0xfedcba98765432a0'u64+uint64(slot))
  registers[0] = RegisterValue(65536)
  registers[1] = RegisterValue(0x1234)
  registers[3] = RegisterValue(65552)
  registers[4] = RegisterValue(0)
  let input = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: registers)
  var frame = newFlatFrame(plan, [dirtyLoopPage], input)
  for warm in 0..<6:
    # Exceed the 64-backedge admission threshold; the stored input is never a prefix destination.
    verifyControl(frame, program, input, 100, [dirtyLoopPage])
    inc dirtyLiveInCases
  let image = pageImage(flatMemorySnapshot(frame), PageIndex(16))
  assert image.error == MachineError.None
  for byteIndex in 0..<16:
    # These literal source bytes are independent of either execution engine's register/memory updates.
    assert image.value.bytes[byteIndex] == byte(0xa0+int(valueSlot))
  when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
    assert flatArmDirtyLoopStatistics(frame)[1] > 0, "store-only loop must enter native"
  for gas in [0'u64, 1, 4, 5, 79, 80, 81, 1000]:
    for budget in [1'u64, 2, 3, 4, 5, 6, 79, 80, 81]:
      # Every unstarted/partial guard must preserve all sentinels before publishing any completed prefix.
      var limited = input
      limited.gas = MachineGas(gas)
      verifyControl(frame, program, limited, budget, [dirtyLoopPage])
      inc dirtyLiveInCases
echo "ARM_DIRTY_LOOP_LIVE_IN_CASES,", dirtyLiveInCases

var nextLoopPage = dirtyLoopPage
nextLoopPage.index = PageIndex(17)
let crossingPages = [dirtyLoopPage, nextLoopPage]
var crossingInfo = dirtyLoopInfo
crossingInfo.registers[0] = RegisterValue(69626)
crossingInfo.registers[3] = RegisterValue(69642)
assert replaceFlatMemoryChecked(dirtyLoopFrame, crossingPages, crossingInfo) == FlatError.None
when defined(pvmArm64Jit):
  let beforeCrossing = flatArmDirtyLoopStatistics(dirtyLoopFrame)
verifyControl(dirtyLoopFrame, dirtyLoopProgram, crossingInfo, 100, crossingPages)
let crossedFirst = pageImage(flatMemorySnapshot(dirtyLoopFrame), PageIndex(16))
let crossedSecond = pageImage(flatMemorySnapshot(dirtyLoopFrame), PageIndex(17))
assert crossedFirst.error == MachineError.None and crossedSecond.error == MachineError.None
assert crossedFirst.value.bytes[4090] == 0x34 and crossedFirst.value.bytes[4095] == 0x39
assert crossedSecond.value.bytes[0] == 0x3a and crossedSecond.value.bytes[9] == 0x43
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  let afterCrossing = flatArmDirtyLoopStatistics(dirtyLoopFrame)
  assert afterCrossing[1] > beforeCrossing[1]
  assert afterCrossing[2] >= beforeCrossing[2]+2 # Each fresh writable page first-touch declines.

# Identity prefix keeps the store base valid for six complete sixteen-store calls despite aliasing.
let aliasLoopProgram = owner([@[198'u8, 0x40, 0], @[120'u8, 0x02, 0],
    @[149'u8, 0x00, 1], @[149'u8, 0x11, 1],
    @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
let aliasLoopPlan = newFlatPlan(aliasLoopProgram, GasCycleLimit(100000))
var aliasLoopFrame = newFlatFrame(aliasLoopPlan, [dirtyLoopPage], dirtyLoopInfo)
for warm in 0..<6:
  verifyControl(aliasLoopFrame, aliasLoopProgram, dirtyLoopInfo, 100, [dirtyLoopPage])
# Six complete sixteen-store runs exceed the hot threshold.
assert aliasLoopFrame.info.registers[0] == RegisterValue(65552)
let aliasMemory = pageImage(flatMemorySnapshot(aliasLoopFrame), PageIndex(16))
assert aliasMemory.error == MachineError.None
assert aliasMemory.value.bytes[0] == 0xa5 and aliasMemory.value.bytes[15] == 0xa5
when defined(pvmArm64Jit):
  assert flatArmDirtyLoopStatistics(aliasLoopFrame) == default(array[3, uint64])
echo "ARM_DIRTY_LOOP_ALIAS_REFUSAL,1"
when defined(pvmArm64Jit) and defined(pvmArmDirtyLoopOwnerReceipt):
  let destroyedBefore = armDirtyLoopArenaDestroyed()
  block:
    var ownerFrame = newFlatFrame(dirtyLoopPlan, [dirtyLoopPage], dirtyLoopInfo)
    for warm in 0..<6:
      verifyControl(ownerFrame, dirtyLoopProgram, dirtyLoopInfo, 100, [dirtyLoopPage])
    when not defined(pvmArm64JitRefuse):
      assert flatArmDirtyLoopStatistics(ownerFrame)[1] > 0
    var active = takeFlatStream(ownerFrame)
    let activeNodes = streamNodes(active)
    var foreign = newFlatFrame(newFlatPlan(dirtyLoopProgram, GasCycleLimit(100000)),
        crossingPages, crossingInfo)
    restoreFlatStream(foreign, active)
    runFlat(foreign, 100)
    assert foreign.reason == StepError.InvalidPreparedProgram
    assert streamNodes(active) == activeNodes
    var fresh = newFlatFrame(dirtyLoopPlan, crossingPages, crossingInfo)
    restoreFlatStream(fresh, active)
    when not defined(pvmArm64JitRefuse):
      let beforeMoveCall = flatArmDirtyLoopStatistics(fresh)
    verifyControl(fresh, dirtyLoopProgram, crossingInfo, 100, crossingPages)
    when not defined(pvmArm64JitRefuse):
      let afterMoveCall = flatArmDirtyLoopStatistics(fresh)
      assert afterMoveCall[0] > beforeMoveCall[0]
      assert afterMoveCall[1] > beforeMoveCall[1]
  when defined(pvmArm64JitRefuse):
    assert armDirtyLoopArenaDestroyed() == destroyedBefore
  else:
    assert armDirtyLoopArenaDestroyed() == destroyedBefore+1
  echo "ARM_DIRTY_LOOP_OWNER,1"
var dirtyLoopCases = 0
for layout in 0..<4:
  var pages: seq[PageImage] = @[]
  if layout < 2:
    var page = dirtyLoopPage
    if layout == 1: page.access = PageAccess.ReadOnly
    pages.add(page)
  assert replaceFlatMemoryChecked(dirtyLoopFrame, pages, dirtyLoopInfo) == FlatError.None
  for paid in [false, true]:
    for gas in [0'u64, 1, 4, 5, 100, 1000, high(uint64)]:
      for budget in [0'u64, 1, 2, 3, 4, 5, 6, 7, 8, 9, 79, 80, 81, 100,
          high(uint64)]:
        var input = dirtyLoopInfo
        if layout == 3:
          input.registers[0] = RegisterValue(65535)
          input.registers[3] = RegisterValue(65551)
        input.gas = MachineGas(gas)
        input.blockCharged = paid
        verifyControl(dirtyLoopFrame, dirtyLoopProgram, input, budget, pages)
        inc dirtyLoopCases
echo "ARM_DIRTY_LOOP_CONTROL_CASES,", dirtyLoopCases

when defined(pvmArm64Jit):
  # A separate shift register permits native four-byte stores after the first checked page touch.
  when defined(pvmArmDirtyLoopOwnerReceipt):
    let wordOwnerBefore = armDirtyLoopArenaDestroyed()
  block:
    let program = owner([@[198'u8, 0x41, 2], @[120'u8, 0x02, 0],
        @[149'u8, 0x00, 1], @[149'u8, 0x44, 8],
        @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
    let plan = newFlatPlan(program, GasCycleLimit(100000))
    let page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
    var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000),
        registers: default(RegisterFile))
    info.registers[0] = RegisterValue(65536)
    info.registers[1] = RegisterValue(0x12345678)
    info.registers[2] = RegisterValue(0xa5)
    info.registers[3] = RegisterValue(65552)
    var frame = newFlatFrame(plan, [page], info)
    for warm in 0..<6:
      verifyControl(frame, program, info, 100, [page])
    let groups = flatArmDirtyWordGroups(frame)
    when defined(pvmArm64JitRefuse):
      assert groups == 0
    else:
      assert groups > 0, "native word store did not execute after the first touch"
    echo "ARM_WORD_GROUPS,", groups
    var controls = 0
    for paid in [false, true]:
      # Every original boundary remains observable around the four-block/20-attempt native group.
      for gas in [0'u64, 4, 5, 14, 15, 19, 20, 21, 1000, high(uint64)]:
        # Include prepaid entry and both sides of one and four original charges.
        for budget in [0'u64, 1, 4, 5, 19, 20, 21, 39, 40, 41, 79, 80, 81, 100, high(uint64)]:
          var input = info
          input.blockCharged = paid
          input.gas = MachineGas(gas)
          verifyControl(frame, program, input, budget, [page])
          inc controls
      for budget in 0'u64..83'u64:
        # Sweep all interior source coordinates across sixteen iterations, not just bulk-entry boundaries.
        var input = info
        input.blockCharged = paid
        verifyControl(frame, program, input, budget, [page])
        inc controls
    var next = page
    next.index = PageIndex(17)
    var crossing = info
    crossing.registers[0] = RegisterValue(69626)
    crossing.registers[3] = RegisterValue(69642)
    for layout in 0..<3:
      # Mixed/missing second pages retain the preceding scalar byte stores before the precise fault.
      var pages = @[page]
      if layout != 2:
        # Two fully writable pages may still decline native batching conservatively at alignment boundaries.
        var last = next
        if layout == 1: last.access = PageAccess.ReadOnly
        pages.add(last)
      assert replaceFlatMemoryChecked(frame, pages, crossing) == FlatError.None
      for paid in [false, true]:
        # The native wrapper declines prepaid prefixes without losing their already charged continuation.
        for gas in [19'u64, 20, 21, 1000]:
          # Affordability and memory refusal must select the same original next attempted instruction.
          for budget in [19'u64, 20, 21, 29, 30, 31, 100]:
            var input = crossing
            input.blockCharged = paid
            input.gas = MachineGas(gas)
            verifyControl(frame, program, input, budget, pages)
            inc controls
    var aligned = crossing
    aligned.registers[0] = RegisterValue(69624)
    aligned.registers[3] = RegisterValue(69640)
    for layout in 0..<3:
      # This aligned entry executes a real word group before reaching the next page's first-touch or fault boundary.
      var pages = @[page]
      if layout != 2:
        # Retain both the all-writable case and a later RO refusal after an earlier committed aggregate.
        var last = next
        if layout == 1: last.access = PageAccess.ReadOnly
        pages.add(last)
      assert replaceFlatMemoryChecked(frame, pages, aligned) == FlatError.None
      for paid in [false, true]:
        # Paid entry still reaches a later native aggregate after its original checked prefix.
        var input = aligned
        input.blockCharged = paid
        let beforeGroups = flatArmDirtyWordGroups(frame)
        verifyControl(frame, program, input, 100, pages)
        when defined(pvmArm64JitRefuse):
          assert flatArmDirtyWordGroups(frame) == 0
        else:
          assert flatArmDirtyWordGroups(frame) > beforeGroups
        inc controls
    assert replaceFlatMemoryChecked(frame, [page], info) == FlatError.None
    for value in [0'u64, 0x80000000'u64, 0xffffffff'u64, 0xdeadbeef'u64, high(uint64)]:
      # Low-word truncation and sign-extended prefix values must preserve four literal stored bytes.
      for shift in [0'u64, 1'u64, 8'u64, 24'u64, 32'u64, 0xffffffffffffffe0'u64]:
        # Aligned high counters wrap normally; nonaligned entries retain the byte loop.
        var input = info
        input.registers[1] = RegisterValue(value)
        input.registers[4] = RegisterValue(shift)
        verifyControl(frame, program, input, 100, [page])
        inc controls
    for length in [0'u64, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17]:
      # Opcode171 is !=, so even an equal/past bound must preserve its do-while byte prefix.
      for upper in [0'u64, 0x100000000'u64]:
        # Branch arithmetic retains full-width address bits independently of effective memory masking.
        var input = info
        input.registers[0] = RegisterValue(65536+upper)
        input.registers[3] = RegisterValue(65536+upper+length)
        verifyControl(frame, program, input, 100, [page])
        inc controls
    var behind = info
    behind.registers[3] = RegisterValue(65535)
    verifyControl(frame, program, behind, 100, [page])
    inc controls
    var top = page
    top.index = PageIndex(1048575)
    var highInfo = info
    highInfo.registers[0] = RegisterValue(high(uint64)-16)
    highInfo.registers[3] = RegisterValue(high(uint64))
    assert replaceFlatMemoryChecked(frame, [top], highInfo) == FlatError.None
    verifyControl(frame, program, highInfo, 100, [top])
    inc controls
    assert controls == 698
    echo "ARM_WORD_CONTROL_CASES,", controls
    when defined(pvmArmDirtyLoopOwnerReceipt):
      var moved = takeFlatStream(frame)
      var successor = newFlatFrame(plan, [page], info)
      restoreFlatStream(successor, moved)
      let beforeMove = flatArmDirtyWordGroups(successor)
      verifyControl(successor, program, info, 100, [page])
      when defined(pvmArm64JitRefuse):
        assert flatArmDirtyWordGroups(successor) == 0
      else:
        assert flatArmDirtyWordGroups(successor) > beforeMove,
            "moved native word image was not reused"
      echo "ARM_WORD_OWNER,1"
  when defined(pvmArmDirtyLoopOwnerReceipt):
    when defined(pvmArm64JitRefuse):
      assert armDirtyLoopArenaDestroyed() == wordOwnerBefore
    else:
      assert armDirtyLoopArenaDestroyed() == wordOwnerBefore+1,
          "native word owner teardown mismatch"


  var wordAliases = 0
  for destination in [0, 1, 3, 4]:
    # Prefix/store dependence is intact, but an overwritten live role must prohibit the native word projection.
    let program = owner([@[198'u8, 0x41, byte(destination)], @[120'u8, byte(destination), 0],
        @[149'u8, 0x00, 1], @[149'u8, 0x44, 8],
        @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
    var info = dirtyLoopInfo
    info.registers[1] = RegisterValue(if destination == 0: 65536 else: 0x12345678)
    var frame = newFlatFrame(newFlatPlan(program, GasCycleLimit(100000)), [dirtyLoopPage], info)
    for warm in 0..<6:
      # Existing positive branch/cache state cannot authorize aliasing dataflow on a later invocation.
      verifyControl(frame, program, info, 100, [dirtyLoopPage])
    for budget in 0'u64..21'u64:
      # Partial original nodes still preserve the source ordering when the wider path declines.
      verifyControl(frame, program, info, budget, [dirtyLoopPage])
      inc wordAliases
    assert flatArmDirtyWordGroups(frame) == 0
  block:
    # Address/data aliasing changes the next extracted byte across a carry within a prospective word.
    let program = owner([@[198'u8, 0x40, 2], @[120'u8, 0x02, 0], @[149'u8, 0x00, 1],
        @[149'u8, 0x44, 8], @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
    var info = dirtyLoopInfo
    info.registers[0] = RegisterValue(65791)
    info.registers[3] = RegisterValue(65807)
    var frame = newFlatFrame(newFlatPlan(program, GasCycleLimit(100000)), [dirtyLoopPage], info)
    for warm in 0..<6:
      # Real byte-native work may run; the unsafe aggregate must remain unadmitted.
      verifyControl(frame, program, info, 100, [dirtyLoopPage])
    let bytes = pageImage(flatMemorySnapshot(frame), PageIndex(16)).value.bytes
    assert bytes[255] == 0xff and bytes[256] == 1
    for budget in 0'u64..21'u64:
      # Every partial boundary around the prospective aggregate is compared to single-step execution.
      verifyControl(frame, program, info, budget, [dirtyLoopPage])
      inc wordAliases
    assert flatArmDirtyWordGroups(frame) == 0
  assert wordAliases == 110
  echo "ARM_WORD_ALIAS_CASES,", wordAliases


var secondStoreControls = 0
let twoStores = owner([@[120'u8, 0x10, 0], @[149'u8, 0, 1], @[149'u8, 0, 1],
    @[149'u8, 0, 1], @[149'u8, 0, 1], @[120'u8, 0x20, 0], @[0'u8]])
var storePage = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))
for index in 0..<4096: storePage.bytes[index] = byte(index mod 256)
for secondAddress in [65535'u64, 0xffffffff'u64, 69632'u64, 69631'u64]:
  # A later checked store can fault after the first native store; its earlier byte and register effects must remain visible.
  let plan = newFlatPlan(twoStores, GasCycleLimit(100000))
  var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
  info.registers[0] = RegisterValue(0xb0)
  info.registers[1] = RegisterValue(65553)
  info.registers[2] = RegisterValue(secondAddress)
  var frame = newFlatFrame(plan, [storePage], info)
  verifyControl(frame, twoStores, info, 100, [storePage])
  when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
    # The retained witness checks real native arithmetic between two checked stores, including a later fault.
    let native = flatArmStatistics(frame)
    assert native[1] > 0 and native[2] >= 4
  for paid in [false, true]:
    for gas in [0'u64, 1, 4, 5, 1000]:
      for budget in 0'u64..8'u64:
        var input = info
        input.gas = MachineGas(gas)
        input.blockCharged = paid
        verifyControl(frame, twoStores, input, budget, [storePage])
        inc secondStoreControls
echo "ARM_CHECKED_STORE_SECOND_EXIT_CASES,", secondStoreControls

when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  proc verifyArmShiftPairs(): array[2, int] =
    ## All coordinate/count/value literals compare the original wrapping shifts; declined patterns retain their existing builder.
    result = default(array[2, int])
    for destination in 0..<13:
      for source in 0..<13:
        let fixture = owner([@[151'u8, byte(source*16+destination), 1],
          @[152'u8, byte(destination*17), 1], @[100'u8, byte(destination*17)], @[0'u8]])
        let first = instructionRegisters(instruction(fixture, CodeAddress(0)))
        let second = instructionRegisters(instruction(fixture, CodeAddress(3)))
        let identity = instructionRegisters(instruction(fixture, CodeAddress(6)))
        assert int(first.destinationIndex) == destination and int(first.bIndex) == source
        for amount in 0..<64:
          # High immediate bits differ deliberately; only their original modulo64 counts may influence the result.
          let jit = newArmJit()
          assert armEntry(jit, 0, 4) == 0
          var body = default(ArmBlock)
          assert emitArmShiftPair(body, first, second, 0x8000000000000000'u64 or uint64(amount),
            0xffffffffffffffc0'u64 or uint64(amount))
          emitArmOperation(body, 100, identity, 0)
          emitArmOperation(body, 100, identity, 0)
          var words = armInstructions(body)
          assert publishArmEntry(jit, 0, 4, 4, words)
          for value in [0'u64, 1, high(uint64), 0x8000000000000000'u64,
              0x0123456789abcdef'u64, 0xfedcba9876543210'u64]:
            var registers = default(RegisterFile)
            for slot in 0..<13: registers[slot] = RegisterValue(0x923456789abcdef0'u64+uint64(slot))
            registers[source] = RegisterValue(value)
            var expected = registers
            expected[destination] = RegisterValue((value shl amount) shr amount)
            assert callArmEntry(jit, 0, registers) == 4
            assert registers == expected
            inc result[0]
        for variant in 0..<3:
          # Distinct destinations, an unchained source or unequal masked counts must preserve both original operations.
          let secondDestination = if variant == 0: (destination+1) mod 13 else: destination
          let secondSource = if variant == 1: (destination+1) mod 13 else: destination
          let broken = owner([@[152'u8, byte(secondSource*16+secondDestination), 1], @[0'u8]])
          let second = instructionRegisters(instruction(broken, CodeAddress(0)))
          let secondAmount = if variant == 2: 2'u64 else: 1'u64
          var body = default(ArmBlock)
          emitArmOperation(body, 100, identity, 0)
          let before = armInstructions(body)
          assert not emitArmShiftPair(body, first, second, 1, secondAmount)
          assert armInstructions(body) == before
          inc result[1]

var armShiftPairCases = 0
var armShiftPairDeclines = 0
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  let shiftPairCounts = verifyArmShiftPairs()
  armShiftPairCases = shiftPairCounts[0]
  armShiftPairDeclines = shiftPairCounts[1]
echo "ARM_SHIFT_PAIR_LITERAL_CASES,", armShiftPairCases
echo "ARM_SHIFT_PAIR_DECLINE_CASES,", armShiftPairDeclines

# The prelude dirties page16 only. A warm native body can then commit its first store
# before a later wide store meets a clean, read-only or absent second page.
let mixedProgram = owner([@[123'u8, 0x18, 0, 0, 0, 0],
    @[123'u8, 0x78, 0xf0, 0xff, 0xff, 0xff],
    @[40'u8, 5, 0, 0, 0], @[130'u8, 0x12, 0, 0, 0, 0],
    @[123'u8, 0x12, 8, 0, 0, 0], @[130'u8, 0x62, 0, 0, 0, 0],
    @[123'u8, 0x72, 0, 0, 0, 0], @[149'u8, 0x44, 1],
    @[171'u8, 0x54, 0xe5, 0xff, 0xff, 0xff], @[0'u8]])
let mixedPlan = newFlatPlan(mixedProgram, GasCycleLimit(100000))
var mixedPage = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
mixedPage.bytes[0] = 0x81
mixedPage.bytes[1] = 0x42
var mixedSecond = PageImage(index: PageIndex(17), access: PageAccess.ReadWrite)
var mixedRegisters = default(RegisterFile)
mixedRegisters[1] = RegisterValue(65536)
mixedRegisters[2] = RegisterValue(0xabcdef0123456789'u64)
mixedRegisters[5] = RegisterValue(20)
mixedRegisters[6] = RegisterValue(65536)
mixedRegisters[7] = RegisterValue(69630)
mixedRegisters[8] = RegisterValue(0x1122334455667788'u64)
let mixedInfo = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000),
    registers: mixedRegisters)
when defined(pvmArm64Jit) and (defined(pvmArmMixedGroupReceipt) or
    defined(pvmArmDirtyLoopOwnerReceipt)) and not defined(pvmArm64JitRefuse):
  for policy in 0..<3:
    # The same mixed source must observe eligible unpriced work, while priced work has no permanent observer.
    var admission = newFlatFrame(mixedPlan, [mixedPage, mixedSecond], mixedInfo)
    if policy == 1:
      let prices = newGasPlan(mixedProgram, GasPlanLimits(bytes: GasPlanByteLimit(65536),
          blocks: GasPlanBlockLimit(1024), cycles: GasCycleLimit(100000)))
      assert prices.error == GasPlanError.None
      assert selectFlatPrices(admission, prices.value, default(GasMemo)) == StepError.None
    elif policy == 2:
      let prices = newGasMemo(mixedProgram, GasMemoLimits(bytes: GasMemoByteLimit(65536),
          cycles: GasCycleLimit(100000)))
      assert prices.error == GasMemoError.None
      assert selectFlatPrices(admission, default(GasPlan), prices.value) == StepError.None
    verifyControl(admission, mixedProgram, mixedInfo, if policy == 0: 10'u64 else: 123'u64,
        [mixedPage, mixedSecond])
    let observers = flatArmMixedProbes(admission)
    assert (if policy == 0: observers > 0 else: observers == 0)
    echo "ARM_MIXED_PRICED_PROBES,", policy, ",", observers
    if policy != 0:
      # A priced frame discards even an unpromoted default-priced observer before execution.
      var unpriced = newFlatFrame(mixedPlan, [mixedPage, mixedSecond], mixedInfo)
      verifyControl(unpriced, mixedProgram, mixedInfo, 10, [mixedPage, mixedSecond])
      assert flatArmMixedProbes(unpriced) > 0
      var retained = takeFlatStream(unpriced)
      restoreFlatStream(admission, retained)
      assert streamNodes(retained) == 0 and flatArmMixedProbes(admission) == 0
      verifyControl(admission, mixedProgram, mixedInfo, 123, [mixedPage, mixedSecond])
      assert flatArmMixedProbes(admission) == 0
      echo "ARM_MIXED_RETAINED_PRICED_PROBES,", policy, ",0"
var mixedFrame = newFlatFrame(mixedPlan, [mixedPage, mixedSecond], mixedInfo)
verifyControl(mixedFrame, mixedProgram, mixedInfo, 123, [mixedPage, mixedSecond])
when defined(pvmArm64Jit):
  when not defined(pvmArm64JitRefuse):
    let warm = flatArmMixedStatistics(mixedFrame)
    assert warm[0] > 0 and warm[1] > 0 and warm[3] >= warm[1]*6
# A new dirty epoch retains the published body. First-page prelude permits the
# first native store; the cross-page store must decline on its clean second page.
verifyControl(mixedFrame, mixedProgram, mixedInfo, 123, [mixedPage, mixedSecond])
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  assert flatArmMixedStatistics(mixedFrame)[2] > 0
mixedSecond.access = PageAccess.ReadOnly
assert replaceFlatMemoryChecked(mixedFrame, [mixedPage, mixedSecond], mixedInfo) == FlatError.None
verifyControl(mixedFrame, mixedProgram, mixedInfo, 123, [mixedPage, mixedSecond])
assert replaceFlatMemoryChecked(mixedFrame, [mixedPage], mixedInfo) == FlatError.None
verifyControl(mixedFrame, mixedProgram, mixedInfo, 123, [mixedPage])
var mixedFault = mixedInfo
mixedFault.registers[6] = RegisterValue(73728) # Later load faults after the first native store changed memory.
verifyControl(mixedFrame, mixedProgram, mixedFault, 123, [mixedPage])
var highest = PageImage(index: PageIndex(1048575), access: PageAccess.ReadWrite)
var highStore = mixedInfo
highStore.registers[7] = RegisterValue(0xfffffff8'u64)
assert replaceFlatMemoryChecked(mixedFrame, [mixedPage, highest], highStore) == FlatError.None
when defined(pvmArm64Jit):
  let beforeHighStore = flatArmMixedStatistics(mixedFrame)
verifyControl(mixedFrame, mixedProgram, highStore, 123, [mixedPage, highest])
assert mixedFrame.exit == StepExit.Panic and mixedFrame.info.pc == CodeAddress(0)
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  let afterHighStore = flatArmMixedStatistics(mixedFrame)
  assert afterHighStore[2] == beforeHighStore[2]+1 and
      afterHighStore[3] == beforeHighStore[3]+3
var highLoad = mixedInfo
highLoad.registers[6] = RegisterValue(0xfffffff8'u64)
when defined(pvmArm64Jit):
  let beforeHighLoad = flatArmMixedStatistics(mixedFrame)
verifyControl(mixedFrame, mixedProgram, highLoad, 123, [mixedPage, highest])
assert mixedFrame.exit == StepExit.Panic and mixedFrame.info.pc == CodeAddress(0)
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  let afterHighLoad = flatArmMixedStatistics(mixedFrame)
  assert afterHighLoad[2] == beforeHighLoad[2]+1 and
      afterHighLoad[3] == beforeHighLoad[3]+2
var wordFirst = mixedPage
wordFirst.index = PageIndex(63)
var wordSecond = mixedSecond
wordSecond.index = PageIndex(64)
var wordBoundary = mixedInfo
wordBoundary.registers[1] = RegisterValue(63'u64*4096)
wordBoundary.registers[6] = RegisterValue(63'u64*4096)
wordBoundary.registers[7] = RegisterValue(64'u64*4096-2)
assert replaceFlatMemoryChecked(mixedFrame, [wordFirst, wordSecond], wordBoundary) == FlatError.None
verifyControl(mixedFrame, mixedProgram, wordBoundary, 123, [wordFirst, wordSecond])
mixedSecond.access = PageAccess.ReadWrite
assert replaceFlatMemoryChecked(mixedFrame, [mixedPage, mixedSecond], mixedInfo) == FlatError.None
for paid in [false, true]:
  for gas in [0'u64, 1, 1000]:
    for budget in [0'u64, 1, 2, 3, 4, 5, 6, 7, 8, 9, 123]:
      var interior = mixedInfo
      interior.pc = CodeAddress(17)
      interior.gas = MachineGas(gas)
      interior.blockCharged = paid
      verifyControl(mixedFrame, mixedProgram, interior, budget, [mixedPage, mixedSecond])
when defined(pvmArm64Jit):
  let mixedStats = flatArmMixedStatistics(mixedFrame)
  when defined(pvmArm64JitRefuse): assert mixedStats == default(array[4, uint64])
  else: assert mixedStats[0] > mixedStats[1] and mixedStats[2] >= 7 and
      mixedStats[3] >= mixedStats[1]*6
  echo "ARM_MIXED_BLOCK,", mixedStats[0], ",", mixedStats[1], ",", mixedStats[2], ",", mixedStats[3]

# The native group must observe the preceding store before its aliased load, then publish
# the loaded value through a later store. The branch repeats enough times to publish the body.
let groupedAliasProgram = owner([@[123'u8, 0x18, 0, 0, 0, 0],
    @[130'u8, 0x19, 0, 0, 0, 0], @[123'u8, 0x19, 8, 0, 0, 0],
    @[171'u8, 0x54, 0xee, 0xff, 0xff, 0xff], @[0'u8]])
let groupedAliasPlan = newFlatPlan(groupedAliasProgram, GasCycleLimit(100000))
var groupedAliasPage = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
var groupedAliasRegisters = default(RegisterFile)
groupedAliasRegisters[1] = RegisterValue(65536)
groupedAliasRegisters[5] = RegisterValue(1)
groupedAliasRegisters[8] = RegisterValue(0x1122334455667788'u64)
groupedAliasRegisters[11] = RegisterValue(0xdeadbeef12345678'u64)
groupedAliasRegisters[12] = RegisterValue(0xfedcba9876543210'u64)
let groupedAliasInfo = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000),
    registers: groupedAliasRegisters)
var groupedAliasFrame = newFlatFrame(groupedAliasPlan, [groupedAliasPage], groupedAliasInfo)
verifyControl(groupedAliasFrame, groupedAliasProgram, groupedAliasInfo, 123,
    [groupedAliasPage])
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  let groupedAliasStats = flatArmMixedStatistics(groupedAliasFrame)
  assert groupedAliasStats[1] > 0
  echo "ARM_MIXED_GROUP_ALIAS,", groupedAliasStats[0], ",", groupedAliasStats[1]
  let groupedWindowStats = flatArmMixedGroupStatistics(groupedAliasFrame)
  echo "ARM_MIXED_GROUP_WINDOW,", groupedWindowStats[0], ",",
      groupedWindowStats[1], ",", groupedWindowStats[2]
  assert groupedWindowStats[0] > 0
  when defined(pvmArmMixedGroupReceipt):
    assert groupedWindowStats[1] > 0 and groupedWindowStats[2] > 0

# A fresh invocation starts with a clean bitmap. Its first grouped store declines, then
# checked execution dirties the page and later loop iterations may use the native window.
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  let groupedBeforeClean = flatArmMixedGroupStatistics(groupedAliasFrame)
verifyControl(groupedAliasFrame, groupedAliasProgram, groupedAliasInfo, 123,
    [groupedAliasPage])
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse) and
    defined(pvmArmMixedGroupReceipt):
  let groupedAfterClean = flatArmMixedGroupStatistics(groupedAliasFrame)
  assert groupedAfterClean[1] > groupedBeforeClean[1] and
      groupedAfterClean[2]-groupedBeforeClean[2] <
      groupedAfterClean[1]-groupedBeforeClean[1]

# A late store crosses an absent next page. The group declines at its first store; the checked
# worker then commits earlier valid stores and reports the actual later fault.
var groupedFutureFault = groupedAliasInfo
groupedFutureFault.registers[1] = RegisterValue(65536+4088)
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  let groupedBeforeFault = flatArmMixedGroupStatistics(groupedAliasFrame)
verifyControl(groupedAliasFrame, groupedAliasProgram, groupedFutureFault, 123,
    [groupedAliasPage])
assert groupedAliasFrame.exit == StepExit.Fault
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse) and
    defined(pvmArmMixedGroupReceipt):
  let groupedAfterFault = flatArmMixedGroupStatistics(groupedAliasFrame)
  assert groupedAfterFault[1] > groupedBeforeFault[1] and
      groupedAfterFault[2] == groupedBeforeFault[2]

# A valid first store near the protected top cannot make the later out-of-range store
# appear valid through a wrapped shared endpoint.
var groupedTopInfo = groupedAliasInfo
groupedTopInfo.registers[1] = RegisterValue(0xfffffff0'u64)
assert replaceFlatMemoryChecked(groupedAliasFrame, [highest], groupedTopInfo) ==
    FlatError.None
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  let groupedBeforeTop = flatArmMixedGroupStatistics(groupedAliasFrame)
verifyControl(groupedAliasFrame, groupedAliasProgram, groupedTopInfo, 123, [highest])
assert groupedAliasFrame.exit == StepExit.Panic
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse) and
    defined(pvmArmMixedGroupReceipt):
  let groupedAfterTop = flatArmMixedGroupStatistics(groupedAliasFrame)
  assert groupedAfterTop[1] > groupedBeforeTop[1] and
      groupedAfterTop[2] == groupedBeforeTop[2]

# Two loads that write the base between candidate members must disable grouping even if both
# loaded values happen to equal the old base in this fixture.
let groupedBaseWriteProgram = owner([@[123'u8, 0x28, 0, 0, 0, 0],
    @[130'u8, 0x18, 0, 0, 0, 0],
    @[130'u8, 0x11, 8, 0, 0, 0], @[130'u8, 0x11, 16, 0, 0, 0],
    @[130'u8, 0x19, 0, 0, 0, 0],
    @[171'u8, 0x54, 0xe2, 0xff, 0xff, 0xff], @[0'u8]])
let groupedBaseWritePlan = newFlatPlan(groupedBaseWriteProgram, GasCycleLimit(100000))
var groupedBaseWritePage = groupedAliasPage
for at in [0, 8, 16]:
  groupedBaseWritePage.bytes[at+2] = 1 # 65536 in little endian.
var groupedBaseWriteInfo = groupedAliasInfo
groupedBaseWriteInfo.registers[2] = RegisterValue(65568)
var groupedBaseWriteFrame = newFlatFrame(groupedBaseWritePlan, [groupedBaseWritePage],
    groupedBaseWriteInfo)
verifyControl(groupedBaseWriteFrame, groupedBaseWriteProgram, groupedBaseWriteInfo, 123,
    [groupedBaseWritePage])
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  assert flatArmMixedStatistics(groupedBaseWriteFrame)[0] == 0
  assert flatArmMixedGroupStatistics(groupedBaseWriteFrame)[0] == 0

# A premarked first page permits an ungrouped native store. The later group spans the
# absent next page, so its first-site exit must preserve that earlier native byte write.
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  let groupedPrefixSource = owner([@[123'u8, 0x28, 0, 0, 0, 0],
      @[123'u8, 0x18, 0, 0, 0, 0], @[130'u8, 0x19, 8, 0, 0, 0],
      @[171'u8, 0x54, 0xee, 0xff, 0xff, 0xff], @[0'u8]])
  var groupedPrefixBody = newArmMixedBody()
  let firstStore = instructionRegisters(instruction(groupedPrefixSource, CodeAddress(0)))
  let groupedStore = instructionRegisters(instruction(groupedPrefixSource, CodeAddress(6)))
  let groupedLoad = instructionRegisters(instruction(groupedPrefixSource, CodeAddress(12)))
  let groupedBranch = instructionRegisters(instruction(groupedPrefixSource, CodeAddress(18)))
  emitArmMixedMemory(groupedPrefixBody, 123, firstStore, 0, 1)
  emitArmMixedWindowMemory(groupedPrefixBody, 123, groupedStore, 0, 2,
      0, 16, 15, true, true)
  emitArmMixedWindowMemory(groupedPrefixBody, 130, groupedLoad, 8, 3,
      0, 16, 15, false, true)
  emitArmMixedBranch(groupedPrefixBody, 171, groupedBranch, 0, 4, 5)
  let groupedPrefixJit = newArmJit()
  assert armEntry(groupedPrefixJit, 0, 5) == 0
  var groupedPrefixWords = armMixedInstructions(groupedPrefixBody)
  assert publishArmEntry(groupedPrefixJit, 0, 4, armMixedLowered(groupedPrefixBody),
      groupedPrefixWords)
  var groupedPrefixBytes = default(array[4096, byte])
  var groupedPrefixRegions = default(array[3, array[3, uint64]])
  groupedPrefixRegions[1] = [65536'u64, 4089'u64,
      cast[uint64](addr groupedPrefixBytes[0])]
  var groupedPrefixDirty = @[1'u64 shl 16]
  var groupedPrefixRegisters = groupedAliasRegisters
  groupedPrefixRegisters[1] = RegisterValue(65536+4088)
  groupedPrefixRegisters[2] = RegisterValue(65536)
  var groupedPrefixState = default(ArmMixedState)
  assert callArmMixed(groupedPrefixJit, 0, groupedPrefixRegisters, groupedPrefixRegions,
      groupedPrefixDirty, groupedPrefixState) == 2
  assert groupedPrefixState[0] == 2 and groupedPrefixState[4] == 1
  assert groupedPrefixBytes[0] == 0x88 and groupedPrefixBytes[1] == 0x77
  assert groupedPrefixBytes[4088] == 0 and groupedPrefixRegisters[11] ==
      groupedAliasRegisters[11]
  echo "ARM_MIXED_GROUP_PREFIX,1,2,1"

# A descriptor with only eight available bytes cannot pass a sixteen-byte read window:
# the len-minus-seven extent is checked before subtracting the additional span.
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  let groupedShortSource = owner([@[130'u8, 0x18, 0, 0, 0, 0],
      @[130'u8, 0x19, 8, 0, 0, 0],
      @[171'u8, 0x54, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
  var groupedShortBody = newArmMixedBody()
  let shortFirst = instructionRegisters(instruction(groupedShortSource, CodeAddress(0)))
  let shortSecond = instructionRegisters(instruction(groupedShortSource, CodeAddress(6)))
  let shortBranch = instructionRegisters(instruction(groupedShortSource, CodeAddress(12)))
  emitArmMixedWindowMemory(groupedShortBody, 130, shortFirst, 0, 1,
      0, 16, 15, true, false)
  emitArmMixedWindowMemory(groupedShortBody, 130, shortSecond, 8, 2,
      0, 16, 15, false, false)
  emitArmMixedBranch(groupedShortBody, 171, shortBranch, 0, 3, 4)
  let groupedShortJit = newArmJit()
  assert armEntry(groupedShortJit, 0, 4) == 0
  var groupedShortWords = armMixedInstructions(groupedShortBody)
  assert publishArmEntry(groupedShortJit, 0, 3, armMixedLowered(groupedShortBody),
      groupedShortWords)
  var groupedShortBytes = default(array[8, byte])
  var groupedShortRegions = default(array[3, array[3, uint64]])
  groupedShortRegions[0] = [65536'u64, 1'u64,
      cast[uint64](addr groupedShortBytes[0])]
  var groupedShortRegisters = groupedAliasRegisters
  var groupedShortDirty: seq[uint64] = @[]
  var groupedShortState = default(ArmMixedState)
  assert callArmMixed(groupedShortJit, 0, groupedShortRegisters, groupedShortRegions,
      groupedShortDirty, groupedShortState) == 1
  assert groupedShortState[0] == 2 and groupedShortState[4] == 0
  assert groupedShortRegisters[8] == groupedAliasRegisters[8] and
      groupedShortRegisters[9] == groupedAliasRegisters[9]
  echo "ARM_MIXED_GROUP_SHORT,1,2,0"

# A folded leading noop leaves the genuine charged header at source PC zero while the first
# executable body node starts at PC one. Ten ordered memory accesses form two stable bases.
let groupedLongProgram = owner([@[2'u8],
    @[123'u8, 0x18, 0, 0, 0, 0], @[130'u8, 0x19, 0, 0, 0, 0],
    @[123'u8, 0x19, 8, 0, 0, 0], @[130'u8, 0x1a, 8, 0, 0, 0],
    @[123'u8, 0x1a, 16, 0, 0, 0], @[130'u8, 0x58, 0, 0, 0, 0],
    @[123'u8, 0x58, 8, 0, 0, 0], @[130'u8, 0x59, 8, 0, 0, 0],
    @[123'u8, 0x59, 16, 0, 0, 0], @[130'u8, 0x5a, 16, 0, 0, 0],
    @[100'u8, 0x66], @[100'u8, 0x66],
    @[171'u8, 0x43, 0xbf, 0xff, 0xff, 0xff], @[0'u8]])
let groupedLongPlan = newFlatPlan(groupedLongProgram, GasCycleLimit(100000))
var groupedLongFirst = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
var groupedLongSecond = PageImage(index: PageIndex(17), access: PageAccess.ReadWrite)
var groupedLongRegisters = groupedAliasRegisters
groupedLongRegisters[1] = RegisterValue(65536)
groupedLongRegisters[3] = RegisterValue(1)
groupedLongRegisters[4] = RegisterValue(0)
groupedLongRegisters[5] = RegisterValue(69632)
let groupedLongInfo = MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000),
    registers: groupedLongRegisters)
var groupedLongFrame = newFlatFrame(groupedLongPlan, [groupedLongFirst,
    groupedLongSecond], groupedLongInfo)
verifyControl(groupedLongFrame, groupedLongProgram, groupedLongInfo, 250,
    [groupedLongFirst, groupedLongSecond])
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  let longMixed = flatArmMixedStatistics(groupedLongFrame)
  let longGroups = flatArmMixedGroupStatistics(groupedLongFrame)
  assert longMixed[0] > 0 and longMixed[1] > 0 and longGroups[0] == 2
  echo "ARM_MIXED_GROUP_LONG,", longMixed[0], ",", longGroups[0]
for paid in [false, true]:
  for gas in [0'u64, 1, 13, 14, 10000]:
    for budget in [0'u64, 1, 2, 7, 13, 14, 15, 28, 250]:
      var interior = groupedLongInfo
      interior.pc = CodeAddress(1)
      interior.gas = MachineGas(gas)
      interior.blockCharged = paid
      verifyControl(groupedLongFrame, groupedLongProgram, interior, budget,
          [groupedLongFirst, groupedLongSecond])

# This admitted source shape has one safe two-store group and thirteen individual accesses.
# Its larger emitted body must decline at publication size, retaining exact checked behavior.
let groupedOversizeProgram = owner([@[123'u8, 0x18, 0, 0, 0, 0],
    @[123'u8, 0x18, 8, 0, 0, 0], @[123'u8, 0x38, 0, 0, 0, 0],
    @[130'u8, 0x33, 0, 0, 0, 0], @[123'u8, 0x38, 0, 0, 0, 0],
    @[123'u8, 0x08, 0, 0, 0, 0], @[123'u8, 0x28, 0, 0, 0, 0],
    @[123'u8, 0x48, 0, 0, 0, 0], @[123'u8, 0x58, 0, 0, 0, 0],
    @[123'u8, 0x68, 0, 0, 0, 0], @[123'u8, 0x78, 0, 0, 0, 0],
    @[123'u8, 0x88, 0, 0, 0, 0], @[123'u8, 0x98, 0, 0, 0, 0],
    @[123'u8, 0xa8, 0, 0, 0, 0], @[123'u8, 0xb8, 0, 0, 0, 0],
    @[170'u8, 0x84, 0xa6, 0xff, 0xff, 0xff], @[0'u8]])
let groupedOversizePlan = newFlatPlan(groupedOversizeProgram, GasCycleLimit(100000))
var groupedOversizeRegisters = default(RegisterFile)
for slot in 0..<12: groupedOversizeRegisters[slot] = RegisterValue(65536)
groupedOversizeRegisters[12] = RegisterValue(0xfedcba9876543210'u64)
let groupedOversizeInfo = MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000),
    registers: groupedOversizeRegisters)
var groupedOversizePage = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
var groupedOversizeFrame = newFlatFrame(groupedOversizePlan, [groupedOversizePage],
    groupedOversizeInfo)
verifyControl(groupedOversizeFrame, groupedOversizeProgram, groupedOversizeInfo, 250,
    [groupedOversizePage])
when defined(pvmArm64Jit) and not defined(pvmArm64JitRefuse):
  var oversizedBody = newArmMixedBody()
  for index in 0..<15:
    let slots = instructionRegisters(instruction(groupedOversizeProgram,
        CodeAddress(uint64(index*6))))
    if index < 2:
      emitArmMixedWindowMemory(oversizedBody, 123, slots, uint32(index*8),
          uint32(index+1), 0, 16, 16, index == 0, true)
    elif index == 3:
      emitArmMixedMemory(oversizedBody, 130, slots, 0, uint32(index+1))
    else:
      emitArmMixedMemory(oversizedBody, 123, slots, 0, uint32(index+1))
  let oversizedBranch = instructionRegisters(instruction(groupedOversizeProgram,
      CodeAddress(90)))
  emitArmMixedBranch(oversizedBody, 170, oversizedBranch, 0, 0, 96)
  let oversizedWords = armMixedInstructions(oversizedBody)
  echo "ARM_MIXED_GROUP_OVERSIZE_LITERAL,", oversizedWords.len
  assert oversizedWords.len >= 1024
  assert flatArmMixedStatistics(groupedOversizeFrame)[0] == 0 and
      flatArmMixedGroupStatistics(groupedOversizeFrame)[0] == 0

# Literal child/driver controls retain same-owner pure code, quotas and publication/retirement behavior.
when defined(pvmArm64Jit):
  block nativeMemoryCycleBackend:
    let dirtySource = owner([@[198'u8, 0x41, 2], @[120'u8, 0x02, 0],
        @[149'u8, 0x00, 1], @[149'u8, 0x11, 1],
        @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
    let prefixSource = owner([@[149'u8, 0x55, 1], @[149'u8, 0x55, 1],
        @[149'u8, 0x55, 1], @[1'u8], @[0'u8]])
    let tailSource = owner([@[57'u8, 6, 0, 0, 1, 0], @[149'u8, 0x33, 2],
        @[173'u8, 0x70, 0, 0, 0, 0], @[0'u8]])
    echo "ARM_MEMORY_CYCLE_BACKEND_CASES,", checkArmMemoryCycleBackend(dirtySource, prefixSource, tailSource)
    let wordDirtySource = owner([@[198'u8, 0x41, 2], @[120'u8, 0x02, 0],
        @[149'u8, 0x00, 1], @[149'u8, 0x44, 8],
        @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
    let writeOnlyPrefix = owner([@[149'u8, 0x55, 1], @[149'u8, 0x55, 1],
        @[149'u8, 0x55, 1], @[51'u8, 12, 42], @[1'u8], @[0'u8]])
    let residentCases = checkArmResidentMemoryCycleBackend(dirtySource, prefixSource, tailSource) +
        checkArmResidentMemoryCycleBackend(wordDirtySource, prefixSource, tailSource) +
        checkArmResidentMemoryCycleBackend(dirtySource, writeOnlyPrefix, tailSource)
    echo "ARM_RESIDENT_MEMORY_CYCLE_BACKEND_CASES,", residentCases
else:
  # This backend is unavailable in a plain interpreter build.
  echo "ARM_MEMORY_CYCLE_BACKEND_CASES,0"
  echo "ARM_RESIDENT_MEMORY_CYCLE_BACKEND_CASES,0"

# A source-shaped native driver must preserve full charged/fault state across 4/5/4 boundaries.
when defined(pvmArm64Jit):
  block nativeMemoryCycleFrame:
    var page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))
    var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000000),
      registers: default(RegisterFile), blockCharged: false)
    for slot in 0..<13: info.registers[slot] = RegisterValue(0x8123456700000000'u64+uint64(slot))
    info.registers[0] = RegisterValue(65536)
    info.registers[1] = RegisterValue(0)
    info.registers[2] = RegisterValue(0)
    info.registers[3] = RegisterValue(0)
    info.registers[4] = RegisterValue(0x80000000ffccbbaa'u64)
    info.registers[5] = RegisterValue(0)
    info.registers[7] = RegisterValue(2)
    info.registers[8] = RegisterValue(3)
    var controls = 0
    for variant in 0..<3:
      # Keep a near-shape refusal and a native prefix with an extra folded source attempt.
      let negative = variant == 1
      let foldedPrefix = variant == 2
      let pieces = if negative: @[@[120'u8, 2, 0],
        @[1'u8],
        @[51'u8, 1, 0],
        @[200'u8, 128, 3],
        @[149'u8, 51, 1],
        @[40'u8, 2],
        @[198'u8, 20, 2],
        @[120'u8, 2, 0],
        @[149'u8, 0, 1],
        @[149'u8, 17, 8],
        @[171'u8, 48, 244, 255, 255, 255],
        @[2'u8],
        @[57'u8, 6, 0, 0, 1, 0],
        @[149'u8, 85, 1],
        @[173'u8, 117, 217, 255, 255, 255],
        @[0'u8]] elif foldedPrefix: @[@[120'u8, 2, 0],
        @[1'u8],
        @[51'u8, 1, 0],
        @[2'u8],
        @[200'u8, 128, 3],
        @[149'u8, 51, 1],
        @[1'u8],
        @[198'u8, 20, 2],
        @[120'u8, 2, 0],
        @[149'u8, 0, 1],
        @[149'u8, 17, 8],
        @[171'u8, 48, 244, 255, 255, 255],
        @[2'u8],
        @[57'u8, 6, 0, 0, 1, 0],
        @[149'u8, 85, 1],
        @[173'u8, 117, 217, 255, 255, 255],
        @[0'u8]] else: @[@[120'u8, 2, 0],
        @[1'u8],
        @[51'u8, 1, 0],
        @[200'u8, 128, 3],
        @[149'u8, 51, 1],
        @[1'u8],
        @[198'u8, 20, 2],
        @[120'u8, 2, 0],
        @[149'u8, 0, 1],
        @[149'u8, 17, 8],
        @[171'u8, 48, 244, 255, 255, 255],
        @[2'u8],
        @[57'u8, 6, 0, 0, 1, 0],
        @[149'u8, 85, 1],
        @[173'u8, 117, 218, 255, 255, 255],
        @[0'u8]]
      let program = owner(pieces)
      let plan = newFlatPlan(program, GasCycleLimit(100000))
      var frame = newFlatFrame(plan, [page], info)
      for warm in 0..<24:
        verifyControl(frame, program, info, 100, [page])
      let warmed = flatArmMemoryCycleStatistics(frame)
      when not defined(pvmArm64JitRefuse):
        if negative: assert warmed[0] == 0
        else:
          assert warmed[0] > 0 and warmed[4] > 0
          assert uint64(frame.info.registers[0]) == 65544
          assert uint64(frame.info.registers[1]) == 32
          assert uint64(frame.info.registers[5]) == 2
          assert uint64(frame.info.registers[6]) == 0xffffffffffccbbaa'u64
      for paid in [false, true]:
        for gas in [0'u64, 1, 2, 3, 4, 7, 26, 27, 28, 44, 45, 46, 100, 999, 1000000, high(uint64)]:
          var input = info
          input.blockCharged = paid
          input.gas = MachineGas(gas)
          for budget in 0'u64..66'u64:
            verifyControl(frame, program, input, budget, [page])
            inc controls
      var missing = page
      missing.index = PageIndex(17)
      var fault = info
      fault.registers[0] = RegisterValue(69632)
      assert replaceFlatMemoryChecked(frame, [missing], fault) == FlatError.None
      let beforeFault = flatArmMemoryCycleStatistics(frame)
      verifyControl(frame, program, fault, 100, [missing])
      let afterFault = flatArmMemoryCycleStatistics(frame)
      when not defined(pvmArm64JitRefuse):
        if not negative:
          assert afterFault[0] == beforeFault[0]+1
          assert afterFault[1] == beforeFault[1]+1
          assert afterFault[2] == beforeFault[2]
          assert afterFault[3] == beforeFault[3]+4
          assert afterFault[4] == beforeFault[4]+1
          assert afterFault[5] == beforeFault[5]+1
      for gas in [0'u64, 30, 100, 1000000]:
        var input = fault
        input.gas = MachineGas(gas)
        for budget in 0'u64..66'u64:
          verifyControl(frame, program, input, budget, [missing])
          inc controls
      var cache = takeFlatStream(frame)
      var fresh = newFlatFrame(plan, [page], info)
      restoreFlatStream(fresh, cache)
      verifyControl(fresh, program, info, 100, [page])
      when not defined(pvmArm64JitRefuse):
        let moved = flatArmMemoryCycleStatistics(fresh)
        if negative: assert moved[0] == 0
        else: assert moved[0] > warmed[0]
      if not negative:
        # Select pricing before emission, then discard a genuinely native default cache at restore.
        for policy in [0, 1]:
          var defaultFrame = newFlatFrame(plan, [page], info)
          for warm in 0..<24: verifyControl(defaultFrame, program, info, 100, [page])
          when not defined(pvmArm64JitRefuse):
            assert flatArmMemoryCycleStatistics(defaultFrame)[0] > 0
          var defaultCache = takeFlatStream(defaultFrame)
          let complete = newGasPlan(program, GasPlanLimits(bytes: GasPlanByteLimit(65536),
            blocks: GasPlanBlockLimit(1024), cycles: GasCycleLimit(100000)))
          let lazy = newGasMemo(program, GasMemoLimits(bytes: GasMemoByteLimit(65536),
            cycles: GasCycleLimit(100000)))
          assert complete.error == GasPlanError.None and lazy.error == GasMemoError.None
          var priced = newFlatFrame(plan, [page], info)
          if policy == 0:
            # An immutable complete plan still cannot borrow the default native driver.
            assert selectFlatPrices(priced, complete.value, default(GasMemo)) == StepError.None
          else:
            # Lazy query/refusal ownership likewise requires fresh price-bearing emission.
            assert selectFlatPrices(priced, default(GasPlan), lazy.value) == StepError.None
          restoreFlatStream(priced, defaultCache)
          assert flatArmMemoryCycleStatistics(priced) == default(array[6, uint64])
          for warm in 0..<24: verifyControl(priced, program, info, 100, [page])
          assert flatArmMemoryCycleStatistics(priced) == default(array[6, uint64])
    echo "ARM_MEMORY_CYCLE_FRAME_CASES,", controls
else:
  # Plain interpreter builds still provide an explicit unavailable coverage record.
  echo "ARM_MEMORY_CYCLE_FRAME_CASES,0"


# Private resident-specific boundaries. This is unqualified until the new emitter is proven active.
when defined(pvmArm64Jit):
  block residentMemoryCycleFrame:
    var controls = 0
    var page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))
    var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000000),
      registers: default(RegisterFile), blockCharged: false)
    for slot in 0..<13: info.registers[slot] = RegisterValue(0x8123456700000000'u64+uint64(slot))
    for slot in 0..3: info.registers[slot] = RegisterValue(0)
    info.registers[0] = RegisterValue(65536)
    info.registers[4] = RegisterValue(0x80000000ffccbbaa'u64)
    info.registers[5] = RegisterValue(0)
    info.registers[7] = RegisterValue(2)
    info.registers[8] = RegisterValue(3)
    for role in 0..<4:
      # Slot12 is write-only at prefix, dirty or read entry. No prelude store hides first-touch refusal.
      let pieces = if role == 0: @[@[2'u8],
        @[1'u8],
        @[51'u8, 12, 0],
        @[200'u8, 128, 3],
        @[149'u8, 51, 1],
        @[1'u8],
        @[198'u8, 196, 2],
        @[120'u8, 2, 0],
        @[149'u8, 0, 1],
        @[149'u8, 204, 8],
        @[171'u8, 48, 244, 255, 255, 255],
        @[2'u8],
        @[57'u8, 6, 0, 0, 1, 0],
        @[149'u8, 85, 1],
        @[173'u8, 117, 218, 255, 255, 255],
        @[0'u8]] elif role == 1: @[@[2'u8],
        @[1'u8],
        @[51'u8, 1, 0],
        @[200'u8, 128, 12],
        @[149'u8, 204, 1],
        @[1'u8],
        @[198'u8, 20, 2],
        @[120'u8, 2, 0],
        @[149'u8, 0, 1],
        @[149'u8, 17, 8],
        @[171'u8, 192, 244, 255, 255, 255],
        @[2'u8],
        @[57'u8, 6, 0, 0, 1, 0],
        @[149'u8, 85, 1],
        @[173'u8, 117, 218, 255, 255, 255],
        @[0'u8]] elif role == 2: @[@[2'u8],
        @[1'u8],
        @[51'u8, 1, 0],
        @[200'u8, 128, 3],
        @[149'u8, 51, 1],
        @[1'u8],
        @[198'u8, 20, 12],
        @[120'u8, 12, 0],
        @[149'u8, 0, 1],
        @[149'u8, 17, 8],
        @[171'u8, 48, 244, 255, 255, 255],
        @[2'u8],
        @[57'u8, 6, 0, 0, 1, 0],
        @[149'u8, 85, 1],
        @[173'u8, 117, 218, 255, 255, 255],
        @[0'u8]] else: @[@[2'u8],
        @[1'u8],
        @[51'u8, 1, 0],
        @[200'u8, 128, 3],
        @[149'u8, 51, 1],
        @[1'u8],
        @[198'u8, 20, 2],
        @[120'u8, 2, 0],
        @[149'u8, 0, 1],
        @[149'u8, 17, 8],
        @[171'u8, 48, 244, 255, 255, 255],
        @[2'u8],
        @[57'u8, 12, 0, 0, 1, 0],
        @[149'u8, 85, 1],
        @[173'u8, 117, 218, 255, 255, 255],
        @[0'u8]]
      let program = owner(pieces)
      let plan = newFlatPlan(program, GasCycleLimit(100000))
      var frame = newFlatFrame(plan, [page], info)
      for warm in 0..<24: verifyControl(frame, program, info, 100, [page])
      when not defined(pvmArm64JitRefuse):
        assert flatArmResidentMemoryCycleActive(frame)
        let stats = flatArmMemoryCycleStatistics(frame)
        assert stats[0] > 0 and stats[4] > 0
      else: assert not flatArmResidentMemoryCycleActive(frame)
      let expected = if role == 0: 32'u64 elif role == 1: 65544'u64
        elif role == 2: 0xff'u64 else: 0xffffffffffccbbaa'u64
      assert uint64(frame.info.registers[12]) == expected
      for paid in [false, true]:
        for gas in [0'u64, 1, 2, 3, 4, 7, 26, 27, 28, 44, 45, 46, 100, 999, 1000000, high(uint64)]:
          var input = info
          input.blockCharged = paid
          input.gas = MachineGas(gas)
          for budget in 0'u64..66'u64:
            verifyControl(frame, program, input, budget, [page])
            inc controls
      for faultKind in 0..<2:
        var bad = page
        if faultKind == 0: bad.access = PageAccess.ReadOnly
        else: bad.index = PageIndex(17)
        assert replaceFlatMemoryChecked(frame, [bad], info) == FlatError.None
        let before = flatArmMemoryCycleStatistics(frame)
        verifyControl(frame, program, info, 100, [bad])
        let after = flatArmMemoryCycleStatistics(frame)
        when not defined(pvmArm64JitRefuse):
          # The native prefix committed; the refused dirty body did not begin or write guest memory.
          assert after[0] == before[0]+1 and after[1] == before[1]+1
          assert after[2] == before[2] and after[3] == before[3] and after[4] == before[4]
          assert after[5] == before[5]+1
        for gas in [3'u64, 4, 7, 26, 27, 28, 1000000]:
          var input = info
          input.gas = MachineGas(gas)
          for budget in 0'u64..66'u64:
            verifyControl(frame, program, input, budget, [bad])
            inc controls
      var cache = takeFlatStream(frame)
      var fresh = newFlatFrame(plan, [page], info)
      restoreFlatStream(fresh, cache)
      verifyControl(fresh, program, info, 100, [page])
      when not defined(pvmArm64JitRefuse): assert flatArmResidentMemoryCycleActive(fresh)
    assert controls == 12328
    echo "ARM_RESIDENT_MEMORY_CYCLE_FRAME_CASES,", controls
else:
  echo "ARM_RESIDENT_MEMORY_CYCLE_FRAME_CASES,0"
