# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Linked x86 Read shift cases share the existing literal cycle and receipt fixture.

proc shiftFixture(spill: bool): NativeReadCycle =
  ## Write six lanes for the complete role bank or seven to force the stack path.
  result = cycleFixture()
  result.read = initNativeReadBody(readHeader, 33, 1, 24, 1)
  for index in 0..<22:
    let op = case index
      of 0: operation(124, 0x36)     # r6 = byte[r3].
      of 1: operation(151, 0x33, 64) # Low register alias, masked zero count.
      of 2: operation(151, 0x66, 0)  # Low register alias, literal zero count.
      of 3: operation(151, 0x67, 63) # High destination, distinct low source.
      of 4: operation(152, 0x77, 63) # High alias, logical result is one.
      of 5: operation(151, 0x79, 5)  # Distinct high source and destination.
      of 6: operation(152, 0xca, 63) # Read guest r12 from the canonical array.
      of 7: operation(151, 0x7b, 2)  # Distinct high source and destination.
      of 8: operation(151, if spill: 0xcc'u8 else: 0xbb'u8, 64)
      of 9: operation(124, 0x36)     # Second checked load for the complete Read certificate.
      else: operation(151, 0xbb, 64) # High alias, masked zero count.
    let offset = uint32(index)+1
    assert addReadBodyOperation(result.read, readHeader+offset, 1+offset, op), "shift Read source"
  let setup = [operation(51, 9, 0x7a), operation(200, 0xb9, 9), operation(149, 0x99, 2)]
  assert addNativeReadContinuation(result.read,
    NativeReadContinuation(header: setupHeader, terminal: 44, price: 3), setup), "shift Setup source"

proc checkShiftEntry(cycle: NativeReadCycle, image: NativeImage,
    encoded: openArray[byte], store: bool) =
  ## Verify full state, bytes, dirty map, destination and ledger through the SysV entry.
  let gas = if store: 31'u64 else: 0'u64
  let remaining = if store: 1000'u64 else: 0'u64
  var registers = default(RegisterFile)
  for slot in 0..<registers.len:
    # Distinguish every untouched lane and retain a high-bit fallback input.
    registers[slot] = RegisterValue(0x1234567800000000'u64+uint64(slot))
  registers[0] = RegisterValue(0x1122334487665544'u64)
  registers[1] = RegisterValue(0)
  registers[3] = RegisterValue(wordAddress)
  registers[4] = RegisterValue(wordAddress+4)
  registers[12] = RegisterValue(0xc000000000000003'u64)
  var expected = registers
  expected[6] = RegisterValue(0x19)
  expected[7] = RegisterValue(1)
  expected[9] = RegisterValue(32)
  expected[10] = RegisterValue(1)
  expected[11] = RegisterValue(4)
  const original = [0x19'u8, 0x2a, 0x3b, 0x4c, 0x6e, 0x7f, 0x80, 0x91]
  var writable = original
  var expectedBytes = original
  const dirtyPage = 1'u64 shl (wordAddress shr 12)
  var dirty = dirtyPage
  var expectedVisits: NativeCycleVisits = [1'u64, 0, 0, 0, 0, 0, 0]
  var last = NativeCycleRole.Read
  var expectedHeader = setupHeader
  if store:
    # The paid Setup and Store commit one word before the unpaid Tail.
    expected[1] = RegisterValue(32)
    expected[2] = RegisterValue(0x87)
    expected[3] = RegisterValue(wordAddress+4)
    expected[9] = RegisterValue(0x80)
    expectedBytes = [0x44'u8, 0x55, 0x66, 0x87, 0x6e, 0x7f, 0x80, 0x91]
    expectedVisits = [1'u64, 1, 1, 0, 0, 0, 0]
    last = NativeCycleRole.Store
    expectedHeader = tailHeader
  var context = NativeCycleContext(
    read: [default(NativeReadRegion), initNativeReadRegion(wordAddress, writable),
      default(NativeReadRegion)],
    writable: [NativeCycleWritable(first: 0x13000),
      NativeCycleWritable(first: wordAddress, length: uint64(writable.len),
        data: cast[pointer](addr writable[0]))],
    dirty: cast[pointer](addr dirty), dirtyWords: 1, gas: gas, remaining: remaining,
    visits: [2'u64, 3, 4, 5, 6, 7, 8], lastCompleted: 9, paidRead: 9)
  let destination = enterNativeReadCycleAbiProof(image, registers, context, encoded)
  assert destination == expectedHeader and nativeCycleSuccessor(cycle, last, registers) ==
      destination,
    "shift destination"
  assert context.gas == 0 and context.remaining == (if store: 976'u64 else: 0'u64)
  assert context.visits == expectedVisits and context.lastCompleted == uint64(ord(last))
  assert context.paidRead == 0 and validNativeCycleReceipt(cycle.layout, destination, gas,
      remaining, context)
  assert registers == expected, "shift full register file"
  assert writable == expectedBytes and dirty == dirtyPage, "shift memory and dirty bitmap"

proc checkResidentReadShifts() =
  ## Run both bank selections and compare installed RX before executing each receipt.
  for spill in [false, true]:
    let cycle = shiftFixture(spill)
    let encoded = x86ReadCycleInstructions(cycle)
    assert encoded.len > 0 and hasCreditReservation(encoded) == (not spill)
    var image = lowerNativeReadCycle(cycle)
    assert image.ready and image.kind == NativeKind.ConnectedReadCycle
    checkShiftEntry(cycle, image, encoded, false)
    checkShiftEntry(cycle, image, encoded, true)
