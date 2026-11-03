# Project-bound suspected compiler reproducer. Standalone reduction remains pending.
import std/[assertions, syncio]
import ../../src/codec/natural
import ../../src/pvm/[program, machine, registers]
import ../../src/pvm/internal/[arm64_jit, handler_stream]

proc appendNatural(bytes: var seq[byte], value: uint64) =
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len: bytes.add(encoded.bytes[index])

proc slotsFor(code: seq[byte]): RegisterSlots =
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

proc actualOperations(jit: ArmJit): uint64 {.noinline.} =
  jit.operations

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
        context[descriptor+3] = flatArmClippedReadRegion(65536, bytes)
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
        let rawBefore = raw.operations
        let clippedBefore = clipped.operations
        let rawResult = callArmMemory(raw, 0, rawInput, rawRegions)
        let clippedResult = callArmMemoryContext(clipped, 0, clippedInput, context)
        let outcome = if size == 8: 37'u32 else: high(uint32)
        assert rawResult == outcome and clippedResult == outcome
        assert rawInput == expected and clippedInput == expected
        let charged = if size == 8: 1'u64 else: 0'u64
        let directRaw = raw.operations
        let directClipped = clipped.operations
        let actualRaw = actualOperations(raw)
        let actualClipped = actualOperations(clipped)
        if size == 8: echo "COUNTER_OBSERVATION,", rawBefore, ",", directRaw, ",", actualRaw, ",", clippedBefore, ",", directClipped, ",", actualClipped
        assert directRaw == rawBefore+charged and directClipped == clippedBefore+charged
        inc widthCases
echo "CLIPPED_WIDTH_NATIVE_CASES,", widthCases
