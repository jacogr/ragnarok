# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Native clipped-read witness called by the supported ARM witness entry point.
import std/[assertions, syncio]
import ../../src/codec/natural
import ../../src/pvm/[program, machine, registers]
import ../../src/pvm/internal/[arm64_jit, handler_stream]

proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Build only the small independent source fixture header for decoded register slots.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len: bytes.add(encoded.bytes[index])

proc slotsFor(code: seq[byte]): RegisterSlots =
  ## Decode one read opcode and its register byte through the public program parser.
  assert code.len == 7
  var bytes: seq[byte] = @[]
  appendNatural(bytes, 0)
  bytes.add(0'u8)
  appendNatural(bytes, uint64(code.len))
  for value in code: bytes.add(value)
  bytes.add(0x41'u8) # Opcode starts at byte offsets 0 and 6.
  let decoded = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(65536),
      JumpCountLimit(1024))
  assert decoded.error == ProgramError.None
  let operation = instruction(decoded.value, CodeAddress(0))
  assert operation.error == ProgramError.None
  instructionRegisters(operation)

proc clippedTestRegion(first: uint64, bytes: var seq[byte]): array[3, uint64] =
  ## Independent test descriptor from the intersection of legal eight-byte start addresses.
  result = [0'u64, 0'u64, 0'u64]
  if bytes.len < 8: return
  let firstLegal = max(first, 65536'u64)
  let lastExclusive = min(first+uint64(bytes.len-7), 0xfffffff8'u64)
  if lastExclusive <= firstLegal: return
  result = [firstLegal, lastExclusive-firstLegal,
      cast[uint64](addr bytes[int(firstLegal-first)])]

proc observedOperations(jit: ArmJit): uint64 {.noinline.} =
  ## Observe the physical counter after calls despite the documented caller-shaped generated-C CSE.
  jit.operations

proc runClippedReadWitness*(): int =
  ## Compare every published clipped native path with the raw 72-byte ABI and full register state.
  let slots = slotsFor(@[130'u8, 16'u8, 0, 0, 0, 0, 0'u8])
  let rawSpanOwner = newArmJit()
  let clippedSpanOwner = newArmJit(clippedReads = true)
  let rawLeafOwner = newArmJit()
  let clippedLeafOwner = newArmJit(clippedReads = true)
  for owner in [rawSpanOwner, clippedSpanOwner, rawLeafOwner, clippedLeafOwner]:
    assert armEntry(owner, 0, 1) == 0

  var rawSpan = default(ArmReadSpan)
  emitArmRead(rawSpan, slots, 0)
  var clippedSpan = default(ArmReadSpan)
  armUseClippedReads(clippedSpan, clippedSpanOwner)
  emitArmRead(clippedSpan, slots, 0)
  var rawSpanWords = armReadInstructions(rawSpan, 37)
  var clippedSpanWords = armReadInstructionsForOwner(clippedSpanOwner, clippedSpan, 37)
  assert rawSpanWords.len-clippedSpanWords.len == 5
  for word in [0xa9448a21'u32, 0xa9460a21'u32, 0xa9478a21'u32,
      0xf9402e22'u32, 0xf9403a22'u32, 0xf9404622'u32]:
    assert word in clippedSpanWords
  assert publishArmEntry(rawSpanOwner, 0, 37, 1, rawSpanWords)
  assert publishArmEntry(clippedSpanOwner, 0, 37, 1, clippedSpanWords)

  var rawLeaf = default(ArmBlock)
  var clippedLeaf = default(ArmBlock)
  var rawLeafWords = armMemoryInstructions(rawLeaf, slots, 0, 37)
  var clippedLeafWords = armMemoryInstructionsForOwner(clippedLeafOwner, clippedLeaf,
      slots, 0, 37)
  assert rawLeafWords.len-clippedLeafWords.len == 5
  for word in [0xa944c422'u32, 0xa9464422'u32, 0xa947c422'u32,
      0xf9402c31'u32, 0xf9403831'u32, 0xf9404431'u32]:
    assert word in clippedLeafWords
  assert publishArmEntry(rawLeafOwner, 0, 37, 1, rawLeafWords)
  assert publishArmEntry(clippedLeafOwner, 0, 37, 1, clippedLeafWords)
  echo "CLIPPED_ISA_SPAN_WORDS,", rawSpanWords.len, ",", clippedSpanWords.len
  echo "CLIPPED_ISA_LEAF_WORDS,", rawLeafWords.len, ",", clippedLeafWords.len

  var cases = 0
  for shape in [(65535'u64, 7), (65535'u64, 8), (65530'u64, 16),
      (65536'u64, 8), (65536'u64, 16), (65539'u64, 41),
      (0xfffffff0'u64, 16), (0xfffffff8'u64, 8)]:
    let first = shape[0]
    let size = int(shape[1])
    var bytes = newSeq[byte](size)
    for index in 0..<size: bytes[index] = byte((index*29+17) mod 256)
    var rawRegions = default(array[3, array[3, uint64]])
    if size >= 8:
      rawRegions[0] = [first, uint64(size-7), cast[uint64](addr bytes[0])]
    var context = default(ArmReadContext)
    context[0] = rawRegions[0]
    context[3] = clippedTestRegion(first, bytes)
    var addresses: seq[uint64] = @[0'u64, 65535'u64, 65536'u64,
        0xfffffff7'u64, 0xfffffff8'u64, first]
    if first > 0: addresses.add(first-1)
    addresses.add(first+uint64(size div 2))
    if size > 0: addresses.add(first+uint64(size-1))
    for address in addresses:
      for upper in [false, true]:
        var initial = default(RegisterFile)
        for slot in 0..<13: initial[slot] = RegisterValue(0x1122334455667700'u64+uint64(slot))
        initial[1] = RegisterValue(address+(if upper: 0x100000000'u64 else: 0'u64))
        let accepted = size >= 8 and address >= 65536'u64 and
            address < 0xfffffff8'u64 and address >= first and
            address-first < uint64(size-7)
        var expected = initial
        if accepted:
          var value = 0'u64
          for octet in 0..<8:
            value = value or (uint64(bytes[int(address-first)+octet]) shl (octet*8))
          expected[0] = RegisterValue(value)
        for route in 0..<2:
          var rawInput = initial
          var clippedInput = initial
          let rawDestination = if route == 0:
            callArmMemory(rawSpanOwner, 0, rawInput, rawRegions)
          else: callArmMemory(rawLeafOwner, 0, rawInput, rawRegions)
          let clippedDestination = if route == 0:
            callArmMemoryContext(clippedSpanOwner, 0, clippedInput, context)
          else: callArmMemoryContext(clippedLeafOwner, 0, clippedInput, context)
          let destination = if accepted: 37'u32 else: high(uint32)
          if rawDestination != destination or clippedDestination != destination or rawInput !=
              expected or clippedInput != expected:
            echo "CLIPPED_FAILURE,", first, ",", size, ",", address, ",", upper, ",", route, ",",
                accepted, ",", rawDestination, ",", clippedDestination, ",", uint64(rawInput[0]),
                    ",",
                uint64(clippedInput[0]), ",", uint64(expected[0])
          assert rawDestination == destination and clippedDestination == destination
          assert rawInput == expected and clippedInput == expected
          inc cases
  echo "CLIPPED_INTERVAL_NATIVE_CASES,", cases

  # Every selected width retains the conservative eight-byte admission boundary.
  # Exercise owner mode, all descriptor positions, empty 0..7-byte regions, and destination/base aliasing.
  var widthCases = 0
  for opcode in 124'u8..130'u8:
    let width = case opcode
      of 124, 125: 1
      of 126, 127: 2
      of 128, 129: 4
      else: 8
    for aliased in [false, true]:
      let destination = if aliased: 1 else: 0
      let selected = slotsFor(@[opcode, byte(16+destination), 0, 0, 0, 0, 0'u8])
      let raw = newArmJit()
      let clipped = newArmJit(clippedReads = true)
      assert armEntry(raw, 0, 1) == 0 and armEntry(clipped, 0, 1) == 0
      var rawBody = default(ArmBlock)
      var clippedBody = default(ArmBlock)
      var rawWords = armMemoryInstructions(rawBody, selected, 0, 37,
          range[124..130](int(opcode)))
      var clippedWords = armMemoryInstructionsForOwner(clipped, clippedBody,
          selected, 0, 37, range[124..130](int(opcode)))
      assert rawWords.len-clippedWords.len == 5
      assert publishArmEntry(raw, 0, 37, 1, rawWords)
      assert publishArmEntry(clipped, 0, 37, 1, clippedWords)
      for descriptor in 0..<3:
        for size in 0..8:
          var bytes = newSeq[byte](size)
          for index in 0..<size: bytes[index] = byte(0x80+index)
          var rawRegions = default(array[3, array[3, uint64]])
          if size >= 8:
            rawRegions[descriptor] = [65536'u64, uint64(size-7), cast[uint64](addr bytes[0])]
          var context = default(ArmReadContext)
          context[descriptor] = rawRegions[descriptor]
          context[descriptor+3] = clippedTestRegion(65536, bytes)
          var initial = default(RegisterFile)
          for slot in 0..<13:
            initial[slot] = RegisterValue(0x1122334455667700'u64+uint64(slot))
          initial[1] = RegisterValue(65536)
          var expected = initial
          if size == 8:
            var value = 0'u64
            for octet in 0..<width:
              value = value or (uint64(bytes[octet]) shl (octet*8))
            if opcode in [125'u8, 127, 129] and (bytes[width-1] and 128) != 0:
              value = value or (high(uint64) shl (width*8))
            expected[destination] = RegisterValue(value)
          var rawInput = initial
          var clippedInput = initial
          let rawBefore = observedOperations(raw)
          let clippedBefore = observedOperations(clipped)
          let rawResult = callArmMemory(raw, 0, rawInput, rawRegions)
          let clippedResult = callArmMemoryContext(clipped, 0, clippedInput, context)
          let outcome = if size == 8: 37'u32 else: high(uint32)
          assert rawResult == outcome and clippedResult == outcome
          assert rawInput == expected and clippedInput == expected
          let charged = if size == 8: 1'u64 else: 0'u64
          assert observedOperations(raw) == rawBefore+charged and
              observedOperations(clipped) == clippedBefore+charged
          inc widthCases
  echo "CLIPPED_WIDTH_NATIVE_CASES,", widthCases

  # Absolute/direct opcodes use the same clipped table, including narrow forms at both fences.
  var directCases = 0
  for opcode in 52'u8..58'u8:
    let selected = slotsFor(@[opcode, 0'u8, 3, 0, 1, 0, 0'u8])
    for boundary in 0..<4:
      let first = if boundary < 2: 65530'u64 else: 0xfffffff0'u64
      let address = case boundary
        of 0: 65535'u32
        of 1: 65536'u32
        of 2: 0xfffffff7'u32
        else: 0xfffffff8'u32
      let accepted = boundary == 1 or boundary == 2
      var bytes = newSeq[byte](16)
      for index in 0..<bytes.len: bytes[index] = byte(0x80+index)
      var rawRegions = default(array[3, array[3, uint64]])
      rawRegions[1] = [first, 9'u64, cast[uint64](addr bytes[0])]
      var context = default(ArmReadContext)
      context[1] = rawRegions[1]
      context[4] = clippedTestRegion(first, bytes)
      let raw = newArmJit()
      let clipped = newArmJit(clippedReads = true)
      assert armEntry(raw, 0, 1) == 0 and armEntry(clipped, 0, 1) == 0
      var rawSpan = default(ArmReadSpan)
      emitArmDirectRead(rawSpan, selected, address, range[52..58](int(opcode)))
      var clippedSpan = default(ArmReadSpan)
      armUseClippedReads(clippedSpan, clipped)
      emitArmDirectRead(clippedSpan, selected, address, range[52..58](int(opcode)))
      var rawWords = armReadInstructions(rawSpan, 37)
      var clippedWords = armReadInstructionsForOwner(clipped, clippedSpan, 37)
      assert rawWords.len-clippedWords.len == 5
      assert publishArmEntry(raw, 0, 37, 1, rawWords)
      assert publishArmEntry(clipped, 0, 37, 1, clippedWords)
      var initial = default(RegisterFile)
      for slot in 0..<13: initial[slot] = RegisterValue(0x1122334455667700'u64+uint64(slot))
      var rawInput = initial
      var clippedInput = initial
      let rawBefore = observedOperations(raw)
      let clippedBefore = observedOperations(clipped)
      let rawResult = callArmMemory(raw, 0, rawInput, rawRegions)
      let clippedResult = callArmMemoryContext(clipped, 0, clippedInput, context)
      let outcome = if accepted: 37'u32 else: high(uint32)
      assert rawResult == outcome and clippedResult == outcome
      assert rawInput == clippedInput
      if accepted: assert rawInput != initial
      else: assert rawInput == initial
      let charged = if accepted: 1'u64 else: 0'u64
      assert observedOperations(raw) == rawBefore+charged and observedOperations(clipped) ==
          clippedBefore+charged
      inc directCases
  echo "CLIPPED_DIRECT_NATIVE_CASES,", directCases

  # Address arithmetic remains modulo 2^32 for both small and negative displacements.
  var wrapCases = 0
  for opcode in [124'u8, 130'u8]:
    let selected = slotsFor(@[opcode, 16'u8, 0, 0, 0, 0, 0'u8])
    for caseIndex in 0..<6:
      let displacement = case caseIndex
        of 0: 1'u32
        of 1: 0xffffffff'u32
        of 2: 65537'u32
        of 5: 1'u32
        else: 0'u32
      let base = case caseIndex
        of 0: 65535'u64
        of 1: 65537'u64
        of 2, 3: 0xffffffff'u64
        of 5: 0xfffffff7'u64
        else: 65535'u64
      let accepted = caseIndex < 3
      let first = if caseIndex == 5: 0xfffffff0'u64 else: 65536'u64
      var bytes = newSeq[byte](16)
      for index in 0..<16: bytes[index] = byte(0x80+index)
      var rawRegions = default(array[3, array[3, uint64]])
      rawRegions[0] = [first, 9'u64, cast[uint64](addr bytes[0])]
      var context = default(ArmReadContext)
      context[0] = rawRegions[0]
      context[3] = clippedTestRegion(first, bytes)
      let raw = newArmJit()
      let clipped = newArmJit(clippedReads = true)
      assert armEntry(raw, 0, 1) == 0 and armEntry(clipped, 0, 1) == 0
      var rawBody = default(ArmBlock)
      var clippedBody = default(ArmBlock)
      var rawWords = armMemoryInstructions(rawBody, selected, displacement, 37,
          range[124..130](int(opcode)))
      var clippedWords = armMemoryInstructionsForOwner(clipped, clippedBody,
          selected, displacement, 37, range[124..130](int(opcode)))
      assert rawWords.len-clippedWords.len == 5
      assert publishArmEntry(raw, 0, 37, 1, rawWords)
      assert publishArmEntry(clipped, 0, 37, 1, clippedWords)
      var initial = default(RegisterFile)
      for slot in 0..<13: initial[slot] = RegisterValue(0x1122334455667700'u64+uint64(slot))
      initial[1] = RegisterValue(base)
      var rawInput = initial
      var clippedInput = initial
      let rawBefore = observedOperations(raw)
      let clippedBefore = observedOperations(clipped)
      let rawResult = callArmMemory(raw, 0, rawInput, rawRegions)
      let clippedResult = callArmMemoryContext(clipped, 0, clippedInput, context)
      let outcome = if accepted: 37'u32 else: high(uint32)
      assert rawResult == outcome and clippedResult == outcome
      assert rawInput == clippedInput
      if accepted: assert rawInput != initial
      else: assert rawInput == initial
      let charged = if accepted: 1'u64 else: 0'u64
      assert observedOperations(raw) == rawBefore+charged and observedOperations(clipped) ==
          clippedBefore+charged
      inc wrapCases
  echo "CLIPPED_WRAP_NATIVE_CASES,", wrapCases

  # A later refusal after a successful speculative read must publish no prior guest write.
  let firstSlots = slotsFor(@[130'u8, 16'u8, 0, 0, 0, 0, 0'u8])
  let secondSlots = slotsFor(@[130'u8, 35'u8, 0, 0, 0, 0, 0'u8])                   # B=2, A=3.
  let rawRollback = newArmJit()
  let clippedRollback = newArmJit(clippedReads = true)
  assert armEntry(rawRollback, 0, 1) == 0 and armEntry(clippedRollback, 0, 1) == 0
  var rawReads = default(ArmReadSpan)
  emitArmRead(rawReads, firstSlots, 0)
  emitArmRead(rawReads, secondSlots, 0)
  var clippedReads = default(ArmReadSpan)
  armUseClippedReads(clippedReads, clippedRollback)
  emitArmRead(clippedReads, firstSlots, 0)
  emitArmRead(clippedReads, secondSlots, 0)
  var rawReadWords = armReadInstructions(rawReads, 37)
  var clippedReadWords = armReadInstructionsForOwner(clippedRollback, clippedReads, 37)
  assert rawReadWords.len-clippedReadWords.len == 10
  assert publishArmEntry(rawRollback, 0, 37, 2, rawReadWords)
  assert publishArmEntry(clippedRollback, 0, 37, 2, clippedReadWords)
  var rollbackBytes = newSeq[byte](16)
  for index in 0..<16: rollbackBytes[index] = byte(0x80+index)
  var rollbackRaw = default(array[3, array[3, uint64]])
  rollbackRaw[0] = [65536'u64, 9'u64, cast[uint64](addr rollbackBytes[0])]
  var rollbackContext = default(ArmReadContext)
  rollbackContext[0] = rollbackRaw[0]
  rollbackContext[3] = clippedTestRegion(65536, rollbackBytes)
  for secondAddress in [65535'u64, 0xfffffff8'u64, 65537'u64]:
    let accepted = secondAddress == 65537'u64
    var initial = default(RegisterFile)
    for slot in 0..<13: initial[slot] = RegisterValue(0x1122334455667700'u64+uint64(slot))
    initial[1] = RegisterValue(65536)
    initial[2] = RegisterValue(secondAddress)
    var rawInput = initial
    var clippedInput = initial
    let rawBefore = observedOperations(rawRollback)
    let clippedBefore = observedOperations(clippedRollback)
    let rawResult = callArmMemory(rawRollback, 0, rawInput, rollbackRaw)
    let clippedResult = callArmMemoryContext(clippedRollback, 0,
        clippedInput, rollbackContext)
    let outcome = if accepted: 37'u32 else: high(uint32)
    assert rawResult == outcome and clippedResult == outcome
    assert rawInput == clippedInput
    if accepted: assert rawInput != initial
    else: assert rawInput == initial
    let charged = if accepted: 2'u64 else: 0'u64
    assert observedOperations(rawRollback) == rawBefore+charged and
        observedOperations(clippedRollback) == clippedBefore+charged
  echo "CLIPPED_ROLLBACK_NATIVE_CASES,3"
  result = cases+widthCases+directCases+wrapCases+3

proc runClippedLegacyAbiRefusal*() =
  ## Both typed bridges enter a published image; a full owner then rejects the raw bridge first.
  let rawOwner = newArmJit()
  let fullOwner = newArmJit(clippedReads = true)
  for owner in [rawOwner, fullOwner]:
    assert armEntry(owner, 0, 1) == 0
    var words = @[0x528004a0'u32, 0xd65f03c0'u32] # MOV W0,#37; RET.
    assert publishArmEntry(owner, 0, 37, 1, words)
  var registers = default(RegisterFile)
  var raw = default(array[3, array[3, uint64]])
  var context = default(ArmReadContext)
  assert callArmMemory(rawOwner, 0, registers, raw) == 37
  assert callArmMemoryContext(fullOwner, 0, registers, context) == 37
  assert observedOperations(rawOwner) == 1 and observedOperations(fullOwner) == 1
  echo "ARM_CLIPPED_ABI_POSITIVE,1,1"
  # A mode assertion must fire before the already published image can run through the raw pointer.
  discard callArmMemory(fullOwner, 0, registers, raw)
  echo "ARM_CLIPPED_ABI_REJECTION_MISSING"
