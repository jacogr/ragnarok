# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise live static fusion through ordinary prepared calls and the real asynchronous runtime.
## A two-block loop leaves a tiny pure prefix intact, trains once, and has a paid memory exit.

import std/assertions
import ../../src/codec/natural
import ../../src/pvm/[program, machine, step]
import ../../src/pvm/internal/[native_pipeline, native_fusion, native_platform,
  native_mixed_loop, native_read_cycle]

proc checkRepeatedFusionReceipt() =
  ## Warm a paid path, then exercise the same key with incorrect live debits and
  ## exit mode. A prior proof must never authorize different returned state.
  let blocks = [
    NativeFusionBlock(header: 10, terminal: 12, span: 2, price: 3, targets: [20'u32, 30]),
    NativeFusionBlock(header: 20, terminal: 23, span: 3, price: 7,
      targets: [high(uint32), high(uint32)], guards: 1)]
  var memo = default(NativeFusionReceipts)
  var state = NativeFusionContext(gas: 90, remaining: 95, visits: 2, paid: 1)
  state.path[0] = 0x0201 # Forward byte order records block one, then block two.
  let proven = checkNativeFusionExit(memo, blocks, 10, 21, 100, 100, state)
  assert proven.valid and proven.paidHeader == 21 and proven.attempted == 5 and proven.branches

  # Reuse the path with different starting budgets and the same exact debits.
  state.gas = 5
  state.remaining = 0
  assert checkNativeFusionExit(memo, blocks, 10, 21, 15, 5, state) == proven

  # Every malformed return must fail even after this source path was authorized.
  assert not checkNativeFusionExit(memo, blocks, 11, 21, 15, 5, state).valid
  assert not checkNativeFusionExit(memo, blocks, 10, 22, 15, 5, state).valid
  assert not checkNativeFusionExit(memo, blocks, 10, 21, 16, 5, state).valid
  assert not checkNativeFusionExit(memo, blocks, 10, 21, 15, 6, state).valid
  state.paid = 0
  assert not checkNativeFusionExit(memo, blocks, 10, 21, 15, 5, state).valid
  state.paid = 1
  assert checkNativeFusionExit(memo, blocks, 10, 21, 15, 5, state) == proven

proc checkLongFusionReceipts() =
  ## Word-boundary paths keep complete identity, exact debits and paid/unpaid exit modes.
  let blocks = [
    NativeFusionBlock(header: 10, terminal: 12, span: 2, price: 3,
      targets: [20'u32, 20], guards: 1),
    NativeFusionBlock(header: 20, terminal: 23, span: 3, price: 7,
      targets: [10'u32, 10], guards: 1)]
  var memo = default(NativeFusionReceipts)
  for count in [1, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64]:
    # Only supported lengths are constructed; the same controls run for each trial horizon.
    if count > NativeFusionVisitLimit: continue
    let debit = uint64((count div 2)*10+(if (count and 1) != 0: 3 else: 0))
    let attempts = uint64((count div 2)*5+(if (count and 1) != 0: 2 else: 0))
    let last = if (count and 1) != 0: 10'u32 else: 20'u32
    let next = if (count and 1) != 0: 20'u32 else: 10'u32
    var state = NativeFusionContext(gas: 1000-debit, remaining: 1000-attempts,
      visits: uint64(count), paid: 0)
    for index in 0..<count:
      # Forward tokens alternate two independently priced source blocks, including repeated visits.
      state.path[index div 8] = state.path[index div 8] or
        (uint64(1+(index and 1)) shl ((index and 7)*8))
    let proven = checkNativeFusionExit(memo, blocks, 10, next, 1000, 1000, state)
    assert proven.valid and proven.paidHeader == 0 and proven.attempted == uint32(attempts)
    assert proven.branches and proven.lastToken == (if (count and 1) != 0: 1'u32 else: 2'u32)
    if (count and 7) != 0:
      # A producer need not clear unwritten bytes from a previous longer entry.
      let word = count div 8
      state.path[word] = state.path[word] or (0xff'u64 shl ((count and 7)*8))
      assert checkNativeFusionExit(memo, blocks, 10, next, 1000, 1000, state) == proven
    let original = state.path
    let middle = count div 2
    state.path[middle div 8] = state.path[middle div 8] and
      not (255'u64 shl ((middle and 7)*8))
    assert not checkNativeFusionExit(memo, blocks, 10, next, 1000, 1000, state).valid
    state.path = original
    dec state.visits
    assert not checkNativeFusionExit(memo, blocks, 10, next, 1000, 1000, state).valid
    state.visits = uint64(count)
    state.paid = 1
    let paid = checkNativeFusionExit(memo, blocks, 10, last+1, 1000, 1000, state)
    assert paid.valid and paid.paidHeader == last+1 and paid.attempted == uint32(attempts)
    state.paid = 0
    assert not checkNativeFusionExit(memo, blocks, 10, last+1, 1000, 1000, state).valid
    state.visits = uint64(NativeFusionVisitLimit)+1
    assert not checkNativeFusionExit(memo, blocks, 10, next, 1000, 1000, state).valid
  var empty = NativeFusionContext(gas: 1000, remaining: 1000)
  empty.path[0] = high(uint64)
  let idle = checkNativeFusionExit(memo, blocks, 10, 10, 1000, 1000, empty)
  assert idle.valid and idle.lastToken == 0
  empty.paid = 1
  assert not checkNativeFusionExit(memo, blocks, 10, 10, 1000, 1000, empty).valid

proc fusionGuest(late: bool = false, wide: bool = false, mode: byte = 0,
    conditional: bool = false, stores: bool = false): Program =
  ## The two loop blocks are independently priced. One has a load after a store,
  ## and the other has an ordinary static branch back to the first.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  template emit(bytes: openArray[byte]) =
    starts.add(code.len)
    for value in bytes: code.add(value)
  template jump(op: openArray[byte], destination: int) =
    let distance = cast[uint32](int32(destination-code.len))
    starts.add(code.len)
    for value in op: code.add(value)
    for index in 0..<4: code.add(byte((distance shr (index*8)) and 255))
  emit([149'u8, 0x77, 1]) # Small incumbent pure prefix.
  emit([149'u8, 0x88, 1])
  emit([120'u8, 0x50, 1]) # Mark the writable page before native entry.
  let first = code.len+5
  jump([40'u8], first)
  assert code.len == first
  emit([2'u8]) # Folded no-op still consumes an original attempt.
  emit([120'u8, 0x50, 0]) # Store byte R0,[R5].
  if stores:
    # All widths of both source immediate-store forms precede the possible paid read fault.
    for width in 0..3:
      let address = 65568'u32+uint32(width*8)
      emit([byte(30+width), 4, byte(address and 255), byte((address shr 8) and 255),
        byte((address shr 16) and 255), 0, 0x80])
      emit([byte(70+width), 0x15, byte(32+width*8), 0x7f])
  if late:
    # A wrapping in-page offset trains with one page but permits a late cross-page fault.
    emit([132'u8, 0x24, 0xff, 0x0f]) # R4 = R2 & 4095.
    emit([200'u8, 0x64, 4]) # R4 = R4 + R6.
    if wide:
      # All13 lanes participate across linked blocks, including full-width aliased writes
      # before the possible paid refusal and a read-only halt sentinel copied into R10.
      emit([149'u8, 0x77, 1])
      emit([149'u8, 0x88, 1])
      emit([100'u8, 0x3a]) # R10 = R3.
      emit([133'u8, 0xbb, 0x80]) # R11 = R11 xor sign-extended -128.
      emit([100'u8, 0xc9]) # R9 = R12 before the later load-and-jump replaces it.
    emit([124'u8, 0x41, 0]) # Read byte R1,[R4].
  else:
    emit([124'u8, 0x61, 0]) # Read byte R1,[R6]. A missing page is a paid fault.
  if conditional:
    # The portable public call independently checks all four conditional forms in a native body.
    emit([147'u8, 0x1a, 0x80])
    emit([148'u8, 0x1b, 0x7f])
    emit([218'u8, 0x1a, 10])
    emit([219'u8, 0x1b, 10])
  emit([149'u8, 0x22, 1]) # One completed iteration per pass.
  var second = 0
  case mode
  of 50:
    emit([50'u8, 4]) # Original R4 selects table ordinal zero without writing a guest lane.
    second = code.len
  of 180:
    emit([180'u8, 0x49, 1, 0x80, 0]) # R9 = sign-extended -128; original R4 selects table ordinal zero.
    second = code.len
  of 181:
    # This fixture mode is opcode180 with an aliased destination/base. Each iteration restores the old base.
    emit([100'u8, 0xa4]) # R4 = original full-width R10, whose low word is4.
    emit([180'u8, 0x44, 1, 2, 0xfe]) # Old R4-2 selects ordinal zero, then R4 becomes2.
    second = code.len
  else:
    second = code.len+7
    jump([80'u8, 0x19, 0x80], second) # Write sign-extended -128 to R9 before the linked target.
    assert code.len == second
  emit([149'u8, 0x99, 1])
  jump([171'u8, 0xc2], first) # Continue while R2 != R12.
  emit([50'u8, 3]) # Dynamic halt sentinel in R3.
  var wire = if mode == 0: @[0'u8, 0] else: @[1'u8, 1]
  let size = encode(JamNatural(uint64(code.len)))
  for index in 0..<size.len: wire.add(size.bytes[index])
  if mode != 0:
    # One original table entry grants only the second block, independently of the native graph.
    assert second < 256
    wire.add(byte(second))
  for value in code: wire.add(value)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for value in mask: wire.add(value)
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(256), JumpCountLimit(1))
  assert decoded.error == ProgramError.None
  decoded.value

when NativeReadCycleEnabled:
  proc fusionLiteralOperation(bytes: openArray[byte]): NativeOperation =
    ## Genuine literal instructions bind private register coordinates independently of either emitter.
    var wire = @[0'u8, 0]
    let length = encode(JamNatural(uint64(bytes.len+1)))
    for index in 0..<length.len: wire.add(length.bytes[index])
    for value in bytes: wire.add(value)
    wire.add(0) # A final panic terminates this small independently marked owner.
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

  proc checkFusionImmediateStores() =
    ## Independent literal bytes check all widths, wrapped A bases and exact precommit guard refusals.
    ## A scalar prefix survives refusal; the suffix and store must remain untouched until retry.
    let prefix = fusionLiteralOperation([149'u8, 0xcc, 1])
    let suffix = fusionLiteralOperation([149'u8, 0xbb, 1])
    for relative in [false, true]:
      for widthIndex in 0..3:
        let width = 1 shl widthIndex
        for base in 0..12:
          if not relative and base != 0: continue # Absolute stores consume no address lane.
          for literal in [0'u32, 0x7fffffff'u32, 0x80000000'u32, high(uint32)]:
            for scenario in 0..9:
              # The normal unaligned case, page split, clean bits, short extent and missing borrows.
              let address = if scenario == 0: 65539'u32
                elif scenario == 7: 65535'u32
                elif scenario == 8: 0xfffffffe'u32
                else: 69631'u32
              let displacement = if relative: 0xffffffff'u32 else: address
              var bytes = @[(if relative: byte(70+widthIndex) else: byte(30+widthIndex)),
                (if relative: byte(0x40+base) else: 4'u8)]
              for index in 0..<4: bytes.add(byte((displacement shr (index*8)) and 255))
              for index in 0..<4: bytes.add(byte((literal shr (index*8)) and 255))
              let store = fusionLiteralOperation(bytes)
              var blocks = [
                NativeFusionBlock(header: 10, terminal: 14, span: 4, price: 3,
                  targets: [20'u32, NativeEntryFailure], guards: 2,
                  branch: NativeOperation(opcode: 40)),
                NativeFusionBlock(header: 20, terminal: 21, span: 1, price: 5,
                  targets: [100'u32, NativeEntryFailure], branch: NativeOperation(opcode: 40))]
              blocks[0].operations[0] = prefix
              blocks[0].operations[1] = store
              blocks[0].operations[2] = suffix
              let image = lowerNativeFusion(blocks)
              assert image.ready, "immediate store image must publish"
              var data = default(array[8192, byte])
              for index in 0..<data.len: data[index] = 0xa5
              var expected = data
              var dirty = [(1'u64 shl 16) or (1'u64 shl 17)]
              if scenario == 2: dirty[0] = dirty[0] and not (1'u64 shl 16)
              if scenario == 3: dirty[0] = dirty[0] and not (1'u64 shl 17)
              var context = NativeFusionContext(gas: 100, remaining: 100)
              context.memory.writable[0] = NativeCycleWritable(first: 0xfffe0000'u64)
              context.memory.writable[1] = NativeCycleWritable(first: 65536, length: uint64(
                  data.len),
                data: addr data[0])
              context.memory.dirty = addr dirty[0]
              context.memory.dirtyWords = 1
              if scenario == 4: context.memory.writable[1].length = 4095
              if scenario == 5: context.memory.writable[1].data = nil
              if scenario == 6: context.memory.dirty = nil
              if scenario == 9: context.memory.dirtyWords = 0
              var registers = default(RegisterFile)
              for lane in 0..12: registers[lane] = RegisterValue(0x1234567800000000'u64+uint64(lane))
              if relative:
                # R12 is advanced by the prefix before address formation, including low-word wrap.
                registers[base] = RegisterValue(0x100000000'u64+uint64(address)+1 -
                  (if base == 12: 1'u64 else: 0'u64))
              var expectedRegisters = registers
              expectedRegisters[12] = RegisterValue(uint64(registers[12])+1)
              let success = scenario in [0, 1] or (scenario == 3 and width == 1)
              if success:
                # Expected bytes use the independent signed32-bit literal equation.
                let value = if literal >= 0x80000000'u32: uint64(literal) or 0xffffffff00000000'u64
                  else: uint64(literal)
                for index in 0..<width: expected[int(address-65536)+index] = byte((value shr (
                    index*8)) and 255)
                expectedRegisters[11] = RegisterValue(uint64(registers[11])+1)
              let next = enterNativeFusion(image, 0, registers, context)
              let diagnostic = "store " & $relative & "/" & $width & "/" & $base &
                "/" & $literal & "/" & $scenario
              assert next == (if success: 100'u32 else: 12'u32), diagnostic & " continuation"
              assert registers == expectedRegisters, diagnostic & " registers"
              assert data == expected, diagnostic & " bytes"
              assert context.gas == (if success: 92'u64 else: 97'u64)
              assert context.remaining == (if success: 95'u64 else: 96'u64)
              assert context.visits == (if success: 2'u64 else: 1'u64)
              assert context.paid == (if success: 0'u64 else: 1'u64)
              let receipt = nativeFusionExit(blocks, 10, next, 100, 100, context)
              # paidHeader identifies the charged block; next identifies its actual failing store.
              assert receipt.valid and receipt.paidHeader == (if success: 0'u32 else: 11'u32),
                diagnostic & " receipt"

  proc checkFusionConditionalMoves() =
    ## Exhaust every register alias, both predicates and full-width nonzero conditions on both ISAs.
    ## Pure leaves expose read-before-write live-ins; linked graphs also exercise x86 SIMD storage.
    for opcode in [147'u8, 148, 218, 219]:
      for destination in 0..12:
        for predicate in 0..12:
          for source in 0..12:
            # Immediate forms encode their destination in A and have no independent value lane.
            if opcode < 190 and source != destination: continue
            let op = if opcode < 190:
                fusionLiteralOperation([opcode, byte(predicate*16+destination), 0x80])
              else: fusionLiteralOperation([opcode, byte(predicate*16+source), byte(destination)])
            assert op.slots.destinationIndex == destination and op.slots.bIndex == predicate
            var span = initNativeSpan(10, 0, 1)
            assert span.add(opcode, op.slots, op.immediate, 0, 12)
            let leaf = lowerNative(span)
            assert leaf.ready
            var blocks = [
              NativeFusionBlock(header: 10, terminal: 12, span: 2, price: 3,
                targets: [20'u32, NativeEntryFailure], branch: NativeOperation(opcode: 40)),
              NativeFusionBlock(header: 20, terminal: 21, span: 1, price: 5,
                targets: [100'u32, NativeEntryFailure], branch: NativeOperation(opcode: 40))]
            blocks[0].operations[0] = op
            var count = 0
            for lane in 0..12:
              # Higher scores for other lanes put the conditional operands in x86 SIMD registers.
              if lane in [destination, predicate, source]: continue
              for repeat in 0..1:
                blocks[1].operations[count] = fusionLiteralOperation([100'u8, byte(lane*17)])
                inc count
            blocks[1].terminal = 21+uint32(count)
            blocks[1].span = 1+uint32(count)
            let image = lowerNativeFusion(blocks)
            assert image.ready and nativeFusionEntry(image, 0)
            for condition in [0'u64, 1, 0x100000000'u64, high(uint64)]:
              # Independent scalar equations use original values, including every overlapping operand.
              var registers = default(RegisterFile)
              for lane in 0..12:
                registers[lane] = RegisterValue(0x123456789abcdef0'u64+uint64(lane))
              registers[predicate] = RegisterValue(condition)
              let before = registers
              var expected = before
              let chosen = if opcode < 190: op.immediate else: uint64(before[source])
              let take = if opcode in [147'u8, 218]: condition == 0 else: condition != 0
              if take: expected[destination] = RegisterValue(chosen)
              assert enterNative(leaf, registers) and registers == expected
              registers = before
              var context = NativeFusionContext(gas: 100, remaining: 100)
              let next = enterNativeFusion(image, 0, registers, context)
              assert next == 100 and registers == expected and context.visits == 2
              assert context.gas == 92 and context.remaining == 97-uint64(count)
              assert context.paid == 0 and context.path[0] == 0x0201
              let receipt = nativeFusionExit(blocks, 10, next, 100, 100, context)
              assert receipt.valid and receipt.attempted == uint32(count+3)

  proc checkFusionIndirectTargets() =
    ## Literal lowering records isolate guarded dynamic entry, alias ordering and paid misses on both ISAs.
    ## They confer no Frame authority; public execution fixtures must independently bind the source graph.
    for opcode in [50'u8, 180]:
      for displacement in [0'u32, 0xfffffffe'u32]:
        let loaded = 0xffffffff80000000'u64
        let immediate = if opcode == 50: cast[uint64](int64(cast[int32](displacement)))
          else: (uint64(displacement) shl 32) or 0x80000000'u64
        let blocks = [
          NativeFusionBlock(header: 10, terminal: 11, span: 1, price: 3,
            targets: [NativeEntryFailure, NativeEntryFailure],
            branch: NativeOperation(opcode: opcode, immediate: immediate)),
          NativeFusionBlock(header: 20, terminal: 21, span: 1, price: 5,
            targets: [100'u32, NativeEntryFailure], indirectEntry: true,
            branch: NativeOperation(opcode: 40))]
        let image = lowerNativeFusion(blocks)
        assert image.ready and nativeFusionEntry(image, 0) and nativeFusionEntry(image, 1)
        for scenario in 0..10:
          # A true hit, source tag/table misses, nil cache, sentinel/wrap refusals and unpaid budgets.
          var cache = default(array[256, uint64])
          cache[0] = (1'u64 shl 32) or 21
          var registers = default(RegisterFile)
          for slot in 0..12: registers[slot] = RegisterValue(0x1234567800000000'u64+uint64(slot))
          let address = case scenario
            of 4: 0'u32
            of 5: 1'u32
            of 6: 0xffff0000'u32
            else: 2'u32
          registers[0] = RegisterValue(0xffffffff00000000'u64 or uint64(address-displacement))
          let before = registers
          var context = NativeFusionContext(gas: 100, remaining: 100, jumps: addr cache)
          if scenario == 1: cache[0] = (2'u64 shl 32) or 21 # Occupied source-cache slot has another ordinal.
          elif scenario == 2: cache[0] = (1'u64 shl 32) or 31 # Resolved checked target has no native entry.
          elif scenario == 3: context.jumps = nil
          elif scenario == 7: context.remaining = 1 # The dynamic edge completes before the successor refuses.
          elif scenario == 8: context.remaining = 0
          elif scenario == 9: context.gas = 2
          elif scenario == 10: context.gas = 3 # The successor's original price is independently enforced.
          let gas = context.gas
          let quota = context.remaining
          let next = enterNativeFusion(image, 0, registers, context)
          let success = scenario in [0, 7, 10]
          let idle = scenario in [8, 9]
          assert next == (if scenario == 0: 100'u32 elif success: 20'u32 elif idle: 10'u32 else: 11'u32)
          assert context.visits == (if scenario == 0: 2'u64 elif idle: 0'u64 else: 1'u64)
          assert context.paid == (if success or idle: 0'u64 else: 1'u64)
          assert context.gas == gas-(if scenario == 0: 8'u64 elif idle: 0'u64 else: 3'u64)
          assert context.remaining == quota-(if scenario == 0: 2'u64 elif idle: 0'u64 else: 1'u64)
          for slot in 0..12:
            # Failed lowering guards preserve even an aliased load; the checked terminal performs its mutation.
            assert uint64(registers[slot]) == (if success and opcode == 180 and slot == 0:
              loaded else: uint64(before[slot]))
          if success: assert context.address == 2 # Captured before the aliased load changes its base.
          let receipt = nativeFusionExit(blocks, 10, next, gas, quota, context)
          assert receipt.valid and receipt.attempted == uint32(quota-context.remaining)
          assert receipt.paidHeader == (if success or idle: 0'u32 else: 11'u32)
        var malformed = blocks
        malformed[0].targets[0] = 20
        assert not lowerNativeFusion(malformed).ready, "dynamic source cannot carry a static target grant"

  proc checkFusionGraphTokens() =
    ## A real255-entry image crosses every receipt byte boundary and reaches token255 on both ISAs.
    ## These literal lowering records test image geometry; only the ordinary public fixtures below
    ## bind execution authority to a Program, gas plan and immutable machine.
    let owner = fusionGuest()
    let original = instruction(owner, CodeAddress(0))
    assert original.error == ProgramError.None
    let slots = instructionRegisters(original)
    var blocks = newSeq[NativeFusionBlock](NativeFusionBlockLimit)
    let outside = NativeEntryLimit-1
    for index in 0..<blocks.len:
      # Each block increments the same full-width lane then follows its unique static successor.
      let header = uint32(index*3)
      blocks[index] = NativeFusionBlock(header: header, terminal: header+2, first: uint32(index*2),
        span: 2, price: 3, targets: [(if index+1 < blocks.len: header+3 else: outside),
          NativeEntryFailure], branch: NativeOperation(opcode: 40))
      blocks[index].operations[0] = NativeOperation(opcode: 149, slots: slots, immediate: 1)
    let image = lowerNativeFusion(blocks)
    assert image.ready and image.codeBytes <= uint64(NativeFusionImageLimit)
    assert nativeFusionEntry(image, NativeFusionBlockLimit-1)
    assert not nativeFusionEntry(image, NativeFusionBlockLimit)
    assert nativeFusionDispatchEntry(image, NativeFusionBlockLimit-1)
    assert not nativeFusionDispatchEntry(image, NativeFusionBlockLimit)
    assert not nativeFusionDispatchEntry(image, -1)
    var memo = default(NativeFusionReceipts)
    for entry in [0, 63, 64, 127, 128, 191, 192, 254]:
      # Entry191 includes token255 as the64th visit; entry254 tests it as the sole visit.
      var registers = default(RegisterFile)
      for slot in 0..12: registers[slot] = RegisterValue(0x1234567800000000'u64+uint64(slot))
      let before = registers
      var context = NativeFusionContext(gas: 10000, remaining: 10000)
      let count = min(NativeFusionVisitLimit, blocks.len-entry)
      let expected = if entry+count == blocks.len: outside else: uint32((entry+count)*3)
      let next = enterNativeFusion(image, entry, registers, context)
      assert next == expected and context.visits == uint64(count) and context.paid == 0
      for slot in 0..12:
        assert uint64(registers[slot]) == uint64(before[slot])+(if slot == 7: uint64(
            count) else: 0'u64)
      let receipt = checkNativeFusionExit(memo, blocks, uint32(entry*3), next, 10000, 10000, context)
      assert receipt.valid and receipt.lastToken == uint32(entry+count)
      assert receipt.attempted == uint32(count*2) and receipt.branches
      assert context.gas == 10000'u64-uint64(count*3)
      assert context.remaining == 10000'u64-uint64(count*2)
      # A proved large-token path never authorizes an internal zero byte on cache reuse.
      let last = count-1
      context.path[last div 8] = context.path[last div 8] and not (255'u64 shl ((last and 7)*8))
      assert not checkNativeFusionExit(memo, blocks, uint32(entry*3), next, 10000, 10000, context).valid
    var idleRegisters = default(RegisterFile)
    var idle = NativeFusionContext(gas: 2, remaining: 10000)
    assert enterNativeFusion(image, NativeFusionBlockLimit-1, idleRegisters, idle) ==
      blocks[NativeFusionBlockLimit-1].header
    assert idle.visits == 0 and idle.gas == 2 and idle.remaining == 10000
    blocks.add(default(NativeFusionBlock))
    assert not lowerNativeFusion(blocks).ready, "a256th graph entry must refuse before publication"

proc assertSameFusionResult(actual, expected: StepResult) =
  ## Checked output owns the independent guest state and attempt accounting oracle.
  assert actual.error == expected.error, "paired step error"
  if expected.error == StepError.None:
    assert actual.value.exit == expected.value.exit, "paired guest exit"
    if expected.value.exit == StepExit.Fault:
      assert uint64(actual.value.faultPage) == uint64(expected.value.faultPage)
    assert machineInfo(actual.value.machine).value == machineInfo(expected.value.machine).value, "paired CPU"
    let observed = memoryOf(actual.value.machine).value
    let reference = memoryOf(expected.value.machine).value
    let observedPages = pageIndices(observed).value
    let referencePages = pageIndices(reference).value
    assert observedPages == referencePages
    for page in referencePages:
      assert pageImage(observed, page).value == pageImage(reference, page).value, "paired memory bytes"

proc checkShortFusionEntries() =
  ## A static predecessor can enter from checked dispatch. Its terminal leaf
  ## stays checked on a direct visit, but must still execute inside the chain.
  var blocks = [
    NativeFusionBlock(header: 4, terminal: 5, span: 1, price: 3,
      targets: [10'u32, NativeEntryFailure], branch: NativeOperation(opcode: 40)),
    NativeFusionBlock(header: 10, terminal: 12, first: 1, span: 2, price: 7,
      targets: [NativeEntryFailure, NativeEntryFailure])]
  blocks[1].operations[0] = NativeOperation(opcode: 51, immediate: 247)
  let shortImage = lowerNativeFusion(blocks)
  assert nativeFusionEntry(shortImage, 0) and nativeFusionEntry(shortImage, 1)
  assert nativeFusionDispatchEntry(shortImage, 0)
  assert not nativeFusionDispatchEntry(shortImage, 1)
  var registers = default(RegisterFile)
  var context = NativeFusionContext(gas: 100, remaining: 16)
  let next = enterNativeFusion(shortImage, 0, registers, context)
  let receipt = nativeFusionExit(blocks, 4, next, 100, 16, context)
  assert receipt.valid and receipt.paidHeader == 11 and receipt.attempted == 3
  assert next == 12 and context.path[0] == 0x0201 and context.visits == 2 and context.gas == 90 and
      context.remaining == 13
  assert uint64(registers[0]) == 247

  # The same two blocks can form a cycle with repeated native links.
  blocks[1].targets[0] = 4
  blocks[1].branch = NativeOperation(opcode: 40)
  let cyclicImage = lowerNativeFusion(blocks)
  assert nativeFusionDispatchEntry(cyclicImage, 0) and nativeFusionDispatchEntry(cyclicImage, 1)

  # Static link counts do not describe runtime-selected indirect paths. Preserve the existing
  # dispatch eligibility of dynamic sources and their staged original-table targets.
  for opcode in [50'u8, 180]:
    blocks[0].targets = [NativeEntryFailure, NativeEntryFailure]
    blocks[0].branch = NativeOperation(opcode: opcode)
    blocks[1].targets = [NativeEntryFailure, NativeEntryFailure]
    blocks[1].branch = default(NativeOperation)
    blocks[1].indirectEntry = true
    let dynamicImage = lowerNativeFusion(blocks)
    assert nativeFusionDispatchEntry(dynamicImage, 0) and nativeFusionDispatchEntry(dynamicImage, 1)
    var cache = default(array[256, uint64])
    cache[0] = (1'u64 shl 32) or 11
    var dynamicRegisters = default(RegisterFile)
    dynamicRegisters[0] = RegisterValue(2)
    var dynamicContext = NativeFusionContext(gas: 100, remaining: 16, jumps: addr cache)
    let dynamicNext = enterNativeFusion(dynamicImage, 0, dynamicRegisters, dynamicContext)
    let dynamicReceipt = nativeFusionExit(blocks, 4, dynamicNext, 100, 16, dynamicContext)
    assert dynamicReceipt.valid and dynamicReceipt.paidHeader == 11 and dynamicReceipt.attempted == 3
    assert dynamicNext == 12 and dynamicContext.path[0] == 0x0201 and dynamicContext.visits == 2
    assert dynamicContext.gas == 90 and dynamicContext.remaining == 13
    assert uint64(dynamicRegisters[0]) == 247

proc checkLateFusionFault(wide: bool)
  ## The late paid-memory fixture is defined below the main supported fusion witness.

proc checkPublicFusion(mode: byte, conditional: bool = false, stores: bool = false) =
  ## Every source-backed branch form must preserve complete CPU/memory state and paid accounting.
  let program = fusionGuest(mode = mode, conditional = conditional, stores = stores)
  let runtime = newNativeRuntime()
  try:
    assert start(runtime)
  except:
    assert false, "static fusion runtime failed to start"
  let jit = newPreparedProgram(program, defaultPreparedLimits(), PvmBackend.Jit, runtime)
  let checked = newPreparedProgram(program, defaultPreparedLimits(), PvmBackend.Interpreted)
  assert jit.error == PreparationError.None and checked.error == PreparationError.None
  let page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
  let memory = captureMemory([page], PageLimit(2)).value
  # The store variant pays eight additional source stores per iteration at the original GP price.
  let fullGas = if stores: 32000000'u64 else: 4000000'u64
  var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(fullGas))
  info.registers[0] = RegisterValue(165)
  info.registers[3] = RegisterValue(0xffff0000'u64)
  info.registers[4] = RegisterValue(2) # The admitted dynamic table has exactly one original destination.
  info.registers[5] = RegisterValue(65536)
  info.registers[6] = RegisterValue(65536)
  if mode == 181: info.registers[10] = RegisterValue(0x1122334400000004'u64)
  info.registers[12] = RegisterValue(90000)
  let source = captureMachine(program, memory, info).value
  let limit = ExecutionStepLimit(2000000)
  let expected = execute(source, limit, checked.value)
  assert expected.error == StepError.None and expected.value.exit == StepExit.Halt, "training oracle must halt"
  assert uint64(machineInfo(expected.value.machine).value.registers[9]) ==
    (if mode in [50'u8, 181]: 90000'u64 else: cast[uint64](-127'i64)), "original terminal write precedes its successor"
  for sample in 0..2:
    # Wait only in the witness, outside invocation, to distinguish queued work from use.
    let outcome = execute(source, limit, jit.value)
    assertSameFusionResult(outcome, expected)
    waitNativeCompiler(runtime)
    let state = preparedInfo(jit.value).value
    if sample == 0: assert state.nativeOperations == 0
    if sample == 1: assert state.nativeOperations < 16 and state.nativeFragments == 2, "training publication"
    if sample == 2:
      # Every original attempt must execute natively, including the alias-reset move and jump terminal.
      let span = (if mode == 181: 8'u64 else: 7'u64)+(if conditional: 4'u64 else: 0'u64) +
        (if stores: 8'u64 else: 0'u64)
      assert state.nativeOperations >= span*90000, "native load-and-jump coverage"

  # A small live quota and low gas enter checked workers at the exact boundary.
  for budget in [4096'u64, 4097, 4098, 4099]:
    let before = preparedInfo(jit.value).value.nativeOperations
    let quota = ExecutionStepLimit(budget)
    let outcome = execute(source, quota, jit.value)
    assert outcome.error == StepError.StepLimitExceeded
    assertSameFusionResult(outcome, execute(source, quota, checked.value))
    assert preparedInfo(jit.value).value.nativeOperations > before+2, "native short quota"
  info.gas = MachineGas(1000)
  let short = captureMachine(program, memory, info).value
  let gasExit = execute(short, limit, jit.value)
  assert gasExit.error == StepError.None and gasExit.value.exit == StepExit.OutOfGas
  assertSameFusionResult(gasExit, execute(short, limit, checked.value))

  if mode != 0:
    # Published graphs still defer invalid/halt terminals to the original worker, including its load write.
    info.gas = MachineGas(fullGas)
    for target in [0'u64, 1'u64, 4'u64, 0xffff0000'u64]:
      if mode == 181:
        # The copied old base is consumed before the aliased literal write, even on panic/halt.
        info.registers[10] = RegisterValue(0x1122334400000000'u64 or (target+2))
      else:
        info.registers[4] = RegisterValue(target)
      let badSource = captureMachine(program, memory, info).value
      let before = preparedInfo(jit.value).value.nativeOperations
      let stopped = execute(badSource, limit, jit.value)
      assert stopped.error == StepError.None
      assert stopped.value.exit == (if target == 0xffff0000'u64: StepExit.Halt else: StepExit.Panic)
      assertSameFusionResult(stopped, execute(badSource, limit, checked.value))
      assert preparedInfo(jit.value).value.nativeOperations > before+2, "native body precedes checked dynamic refusal"
      if mode == 180:
        assert uint64(machineInfo(stopped.value.machine).value.registers[9]) == cast[uint64](-128'i64)
      elif mode == 181:
        assert uint64(machineInfo(stopped.value.machine).value.registers[4]) == 2
    info.registers[4] = RegisterValue(2)
    if mode == 181: info.registers[10] = RegisterValue(0x1122334400000004'u64)

  # The prefix dirties the page. The linked store must commit before the paid
  # read fault returns with the same reservation and original guest PC.
  info.gas = MachineGas(fullGas)
  info.registers[6] = RegisterValue(69632)
  let missing = captureMachine(program, memory, info).value
  let beforeFault = preparedInfo(jit.value).value.nativeOperations
  let fault = execute(missing, limit, jit.value)
  assert preparedInfo(jit.value).value.nativeOperations == beforeFault+4 +
    (if stores: 8'u64 else: 0'u64), "native paid prefix"
  assert fault.error == StepError.None and fault.value.exit == StepExit.Fault
  assertSameFusionResult(fault, execute(missing, limit, checked.value))
  assert machineInfo(fault.value.machine).value.blockCharged
  assert load(memoryOf(fault.value.machine).value, MemoryAddress(65536),
    AccessWidth(1)).value == RegisterValue(165)

  # Supply the missing page and resume the exact paid suffix through the same cached owner.
  let extra = PageImage(index: PageIndex(17), access: PageAccess.ReadOnly)
  let repaired = withPage(memoryOf(fault.value.machine).value, extra)
  assert repaired.error == MachineError.None
  let resumed = withMemory(fault.value.machine, repaired.value)
  assert resumed.error == MachineError.None
  assertSameFusionResult(execute(resumed.value, limit, jit.value),
    execute(resumed.value, limit, checked.value))
  assert close(runtime)

proc runStaticFusion*() =
  ## Exercise raw geometry/refusal controls, then ordinary prepared calls through every supported branch form.
  checkRepeatedFusionReceipt()
  checkLongFusionReceipts()
  when NativeReadCycleEnabled:
    checkFusionConditionalMoves()
    checkFusionImmediateStores()
    checkFusionGraphTokens()
    checkFusionIndirectTargets()
    checkShortFusionEntries()
  for mode in [0'u8, 50, 180, 181]:
    checkPublicFusion(mode)
  checkPublicFusion(0, conditional = true)
  checkPublicFusion(0, stores = true)
  checkLateFusionFault(wide = false)
  checkLateFusionFault(wide = true)

proc checkLateFusionFault(wide: bool) =
  ## A paid read in the 49th linked block must retain all earlier stores and exact accounting.
  let program = fusionGuest(late = true, wide = wide)
  let runtime = newNativeRuntime()
  try:
    assert start(runtime)
  except:
    assert false, "late fusion runtime failed to start"
  let jit = newPreparedProgram(program, defaultPreparedLimits(), PvmBackend.Jit, runtime)
  let checked = newPreparedProgram(program, defaultPreparedLimits(), PvmBackend.Interpreted)
  assert jit.error == PreparationError.None and checked.error == PreparationError.None
  let capturedMemory = captureMemory([PageImage(index: PageIndex(16),
      access: PageAccess.ReadWrite)],
    PageLimit(2))
  assert capturedMemory.error == MachineError.None
  let memory = capturedMemory.value
  var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(8000000))
  info.registers[0] = RegisterValue(165)
  if wide:
    # Nonzero high words expose accidental MOVD truncation of ordinary guest values.
    info.registers[0] = RegisterValue(0xdeadbeef000000a5'u64)
    for slot in [7, 8, 10, 11]:
      info.registers[slot] = RegisterValue(0x1234567800000000'u64+uint64(slot))
  info.registers[3] = RegisterValue(0xffff0000'u64)
  info.registers[5] = RegisterValue(65536)
  info.registers[6] = RegisterValue(65536)
  info.registers[12] = RegisterValue(90000)
  let captured = captureMachine(program, memory, info)
  assert captured.error == MachineError.None
  let source = captured.value
  let limit = ExecutionStepLimit(2000000)
  let expected = execute(source, limit, checked.value)
  assert expected.error == StepError.None and expected.value.exit == StepExit.Halt
  for sample in 0..2:
    # Publish the ordinary seed, then train and collect the same two-block fusion graph.
    assertSameFusionResult(execute(source, limit, jit.value), expected)
    waitNativeCompiler(runtime)
  assert preparedInfo(jit.value).value.nativeFragments == 2
  info.registers[6] = RegisterValue(65536+4096-24)
  let late = captureMachine(program, memory, info)
  assert late.error == MachineError.None
  let before = preparedInfo(jit.value).value.nativeOperations
  let fault = execute(late.value, limit, jit.value)
  assertSameFusionResult(fault, execute(late.value, limit, checked.value))
  assert fault.error == StepError.None and fault.value.exit == StepExit.Fault
  assert preparedInfo(jit.value).value.nativeOperations == before+uint64(2+24*(
      if wide: 14 else: 9)+(if wide: 9 else: 4)),
    "late native progress: " & $(preparedInfo(jit.value).value.nativeOperations-before)
  let cpu = machineInfo(fault.value.machine).value
  assert uint64(cpu.registers[2]) == 24 and cpu.blockCharged, "late counter/paid state"
  assert uint64(fault.value.faultPage) == 17'u64*4096, "late fault page address"
  assert load(memoryOf(fault.value.machine).value, MemoryAddress(65536), AccessWidth(1)).value ==
    RegisterValue(165)
  assert pageImage(memory, PageIndex(16)).value.bytes[0] == 0
  assert machineInfo(late.value).value == info
  assert close(runtime)
