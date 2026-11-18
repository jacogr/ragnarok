# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise live static fusion through ordinary prepared calls and the real asynchronous runtime.
## A two-block loop leaves a tiny pure prefix intact, trains once, and has a paid memory exit.

import std/assertions
import ./pvm_memory_windows
import ../../src/codec/natural
import ../../src/pvm/[program, machine, step]
import ../../src/pvm/internal/[dynamic_jump_cache, native_pipeline, native_fusion, native_platform, native_read_body]
when NativeReadCycleEnabled and defined(pvmSharedAsyncWitness):
  import ./pvm_fusion_composition
  import ../../src/pvm/internal/handler_stream

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

proc checkCollidingFusionReceipts() =
  ## These independent one-visit receipts collide in bucket 1203 in the 2048-slot cache.
  ## Alternating them must preserve complete source/debit identity, including after a cache hit.
  let blocks = [
    NativeFusionBlock(header: 10, terminal: 11, span: 1, price: 3,
      targets: [638'u32, NativeEntryFailure], branch: NativeOperation(opcode: 40)),
    NativeFusionBlock(header: 20, terminal: 21, first: 1, span: 1, price: 7,
      targets: [5625'u32, NativeEntryFailure], branch: NativeOperation(opcode: 40))]
  var memo = default(NativeFusionReceipts)
  for trial in 0..7:
    # Literal next headers and source tokens exercise the same occupied bucket in both directions.
    let index = trial and 1
    let entry = blocks[index].header
    let next = blocks[index].targets[0]
    var state = NativeFusionContext(gas: 100-blocks[index].price, remaining: 99, visits: 1)
    state.path[0] = uint64(index+1)
    let proven = nativeFusionExit(blocks, entry, next, 100, 100, state)
    assert proven.valid and proven.branches and proven.paidHeader == 0
    assert proven.attempted == 1 and proven.lastToken == uint32(index+1)
    # Check both proof construction and immediate reuse before changing a live key field.
    for repeat in 0..1:
      assert checkNativeFusionExit(memo, blocks, entry, next, 100, 100, state) == proven
    assert not checkNativeFusionExit(memo, blocks, entry+1, next, 100, 100, state).valid
    assert not checkNativeFusionExit(memo, blocks, entry, next+1, 100, 100, state).valid
    assert not checkNativeFusionExit(memo, blocks, entry, next, 101, 100, state).valid
    assert not checkNativeFusionExit(memo, blocks, entry, next, 100, 101, state).valid
    state.paid = 1
    assert not checkNativeFusionExit(memo, blocks, entry, next, 100, 100, state).valid
    state.paid = 0
    state.path[0] = state.path[0] or 0xff00 # Unwritten tail bytes retain no authority.
    assert checkNativeFusionExit(memo, blocks, entry, next, 100, 100, state) == proven

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
    conditional: bool = false, windows: bool = false, hostPrelude: int = 0,
    scalarOnly: bool = false, pressureEntry = false): Program =
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
  for index in 0..<hostPrelude:
    # Each short host block is independently priced before the long loop.
    emit([10'u8, 42])
  let first = code.len+5
  jump([40'u8], first)
  assert code.len == first
  emit([2'u8]) # Folded no-op still consumes an original attempt.
  if windows:
    # An ordered store prefix precedes nearby signed reads and a separate nearby write group.
    emit([120'u8, 0x50, 0])
    emit([132'u8, 0x24, 7]) # R4 = R2 & 7 keeps training within one page.
    emit([200'u8, 0x64, 4])
    emit([127'u8, 0x41, 0])
    emit([215'u8, 0xa9, 11]) # Clobber x86 R8 scratch between the grouped reads.
    emit([127'u8, 0x4a, 8])
    emit([121'u8, 0x51, 0])
    emit([121'u8, 0x5a, 8])
  elif not scalarOnly:
    # The scalar fixture omits only these memory operations; every original edge is unchanged.
    emit([120'u8, 0x50, 0]) # Store byte R0,[R5].
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
  if hostPrelude != 0:
    # The hot source graph can publish at this real host boundary before final halt.
    emit([10'u8, 43])
  emit([50'u8, 3]) # Dynamic halt sentinel in R3.
  if pressureEntry:
    # An alternate entry emits a new node before the otherwise identical hot path.
    jump([40'u8], 0)
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
  let decoded = decodeProgram(wire, CodeAddress(0),
    ProgramByteLimit(if hostPrelude == 0: 128 else: 16384), JumpCountLimit(1))
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
    wire.add(byte(1 or (1 shl bytes.len)))
    let owner = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(32), JumpCountLimit(0))
    assert owner.error == ProgramError.None
    let decoded = instruction(owner.value, CodeAddress(0))
    assert decoded.error == ProgramError.None
    NativeOperation(opcode: decoded.value.opcode, slots: instructionRegisters(decoded),
      immediate: uint64(decoded.value.x))

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
        for scenario in 0..13:
          # A true hit, source tag/table misses, nil cache, sentinel/wrap refusals and unpaid budgets.
          var cache = default(DynamicJumpTags)
          cache[0] = (1'u64 shl 32) or 21
          var registers = default(RegisterFile)
          for slot in 0..12: registers[slot] = RegisterValue(0x1234567800000000'u64+uint64(slot))
          let address = case scenario
            of 4: 0'u32
            of 5: 1'u32
            of 6: 0xffff0000'u32
            of 11, 12: 514'u32 # A valid ordinal whose bucket lies in the expanded upper bank.
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
          if scenario in [11, 12]:
            # Upper-bank hits still require the complete original table tag.
            cache[256] = (uint64(if scenario == 11: 257 else: 1) shl 32) or 21
          elif scenario == 13:
            # A matching tag in another bucket grants no associative fallback authority.
            cache[0] = (1'u64 shl 32) or 31
            cache[256] = (1'u64 shl 32) or 21
          let gas = context.gas
          let quota = context.remaining
          let next = enterNativeFusion(image, 0, registers, context)
          let completed = scenario in [0, 11]
          let success = completed or scenario in [7, 10]
          let idle = scenario in [8, 9]
          assert next == (if completed: 100'u32 elif success: 20'u32 elif idle: 10'u32 else: 11'u32)
          assert context.visits == (if completed: 2'u64 elif idle: 0'u64 else: 1'u64)
          assert context.paid == (if success or idle: 0'u64 else: 1'u64)
          assert context.gas == gas-(if completed: 8'u64 elif idle: 0'u64 else: 3'u64)
          assert context.remaining == quota-(if completed: 2'u64 elif idle: 0'u64 else: 1'u64)
          for slot in 0..12:
            # Failed lowering guards preserve even an aliased load; the checked terminal performs its mutation.
            assert uint64(registers[slot]) == (if success and opcode == 180 and slot == 0:
              loaded else: uint64(before[slot]))
          if success:
            # Captured before the aliased load changes its base.
            assert context.address == uint64(address)
          let receipt = nativeFusionExit(blocks, 10, next, gas, quota, context)
          assert receipt.valid and receipt.attempted == uint32(quota-context.remaining)
          assert receipt.paidHeader == (if success or idle: 0'u32 else: 11'u32)
        var malformed = blocks
        malformed[0].targets[0] = 20
        assert not lowerNativeFusion(malformed).ready, "dynamic source cannot carry a static target grant"

  proc checkDenseFusionGuards() =
    ## Dense guarded bodies must fit without duplicating restoration for every paid site.
    ## Alternating source bases keep every guard independent even when their live values agree.
    ## Literal source operands grant no Frame authority. Each native return is checked before replay.
    let source = decodeProgram([0'u8, 0, 13, 124, 0x41, 0, 124, 0x51, 0, 149, 0x77, 1,
      149, 0x88, 1, 0, 0x49, 0x12], CodeAddress(0), ProgramByteLimit(32), JumpCountLimit(0))
    assert source.error == ProgramError.None
    let read = instruction(source.value, CodeAddress(0))
    let alternate = instruction(source.value, CodeAddress(3))
    let increment = instruction(source.value, CodeAddress(6))
    let successor = instruction(source.value, CodeAddress(9))
    assert read.error == ProgramError.None and alternate.error == ProgramError.None and
      increment.error == ProgramError.None and
      successor.error == ProgramError.None
    var bytes = default(array[15, byte])
    for index in 0..<bytes.len: bytes[index] = byte(index+1)
    for indirect in [false, true]:
      # Static and original-table-linked paths exercise both restoration layouts.
      var blocks = [
        NativeFusionBlock(header: 10, terminal: 27, span: 17, price: 19, guards: 0x7fff,
          targets: [40'u32, NativeEntryFailure], branch: NativeOperation(opcode: 40)),
        NativeFusionBlock(header: 40, terminal: 42, first: 17, span: 2, price: 5,
          targets: [100'u32, NativeEntryFailure], indirectEntry: indirect,
          branch: NativeOperation(opcode: 40))]
      for index in 0..<bytes.len:
        blocks[0].operations[index] = NativeOperation(opcode: 124,
          slots: instructionRegisters(if (index and 1) == 0: read else: alternate),
          immediate: uint64(index))
      blocks[0].operations[15] = NativeOperation(opcode: 149,
        slots: instructionRegisters(increment), immediate: 1)
      blocks[1].operations[0] = NativeOperation(opcode: 149,
        slots: instructionRegisters(successor), immediate: 1)
      if indirect:
        # The copied dynamic terminal consumes original R0 before any target work.
        blocks[0].targets = [NativeEntryFailure, NativeEntryFailure]
        blocks[0].branch = NativeOperation(opcode: 50)
      let image = lowerNativeFusion(blocks)
      assert image.ready and nativeFusionEntry(image, 0) and nativeFusionEntry(image, 1)
      var tags = default(DynamicJumpTags)
      tags[0] = (1'u64 shl 32) or 41
      var initial = default(RegisterFile)
      for slot in 0..12: initial[slot] = RegisterValue(0x1234567800000000'u64+uint64(slot))
      initial[0] = RegisterValue(0x1234567800000002'u64)
      initial[4] = RegisterValue(0x1234567800010000'u64)
      initial[5] = initial[4]
      for accessible in 0..bytes.len:
        # Clip the same original extent at each guard; earlier writes survive the first failed load.
        var registers = initial
        var expected = initial
        var context = NativeFusionContext(gas: 100, remaining: 100, jumps: addr tags)
        if accessible != 0:
          context.memory.read[0] = initNativeReadRegion(65536, bytes.toOpenArray(0, accessible-1))
          expected[1] = RegisterValue(uint64(accessible))
        let completed = accessible == bytes.len
        if completed:
          expected[7] = RegisterValue(uint64(initial[7])+1)
          expected[8] = RegisterValue(uint64(initial[8])+1)
        let next = enterNativeFusion(image, 0, registers, context)
        assert registers == expected
        assert next == (if completed: 100'u32 else: 11'u32+uint32(accessible))
        assert context.visits == (if completed: 2'u64 else: 1'u64)
        assert context.paid == (if completed: 0'u64 else: 1'u64)
        assert context.gas == (if completed: 76'u64 else: 81'u64)
        assert context.remaining == (if completed: 81'u64 else: 83'u64)
        let receipt = nativeFusionExit(blocks, 10, next, 100, 100, context)
        assert receipt.valid and receipt.paidHeader == (if completed: 0'u32 else: 11'u32)
        assert receipt.attempted == (if completed: 19'u32 else: 17'u32)
      for budget in 0..3:
        # Refusal before either reservation restores every host lane and exact unpaid ledger.
        let gas = if budget == 0: 18'u64 elif budget == 2: 19'u64 else: 100'u64
        let quota = if budget == 1: 16'u64 elif budget == 3: 17'u64 else: 100'u64
        var registers = initial
        var expected = initial
        var context = NativeFusionContext(gas: gas, remaining: quota, jumps: addr tags)
        context.memory.read[0] = initNativeReadRegion(65536, bytes)
        let completed = budget >= 2
        if completed:
          expected[1] = RegisterValue(15)
          expected[7] = RegisterValue(uint64(initial[7])+1)
        let next = enterNativeFusion(image, 0, registers, context)
        assert registers == expected and next == (if completed: 40'u32 else: 10'u32)
        assert context.visits == uint64(ord(completed)) and context.paid == 0
        assert context.gas == gas-(if completed: 19'u64 else: 0'u64)
        assert context.remaining == quota-(if completed: 17'u64 else: 0'u64)
        assert nativeFusionExit(blocks, 10, next, gas, quota, context).valid
      for index in 0..<bytes.len: assert bytes[index] == byte(index+1)

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

proc assertSameFusionMachine(actual, expected: Machine) =
  ## Compare immutable CPU, page membership and every committed byte at halt or a host boundary.
  assert machineInfo(actual).value == machineInfo(expected).value, "paired CPU"
  let observed = memoryOf(actual).value
  let reference = memoryOf(expected).value
  let observedPages = pageIndices(observed).value
  let referencePages = pageIndices(reference).value
  assert observedPages == referencePages
  for page in referencePages:
    assert pageImage(observed, page).value == pageImage(reference, page).value, "paired memory bytes"

proc assertSameFusionResult(actual, expected: StepResult) =
  ## Checked output owns the independent guest state and attempt accounting oracle.
  assert actual.error == expected.error, "paired step error"
  if expected.error == StepError.None:
    assert actual.value.exit == expected.value.exit, "paired guest exit"
    if expected.value.exit == StepExit.Fault:
      assert uint64(actual.value.faultPage) == uint64(expected.value.faultPage)
    assertSameFusionMachine(actual.value.machine, expected.value.machine)

when NativeReadCycleEnabled:
  # Keep native-only API references out of unsupported and checked-only module profiles.
  type FusionHostContext = object
    ## Callback observations and mapping selection remain host-owned.
    calls, prelude: int
    remap: bool
    trace: seq[Machine]

  proc continueFusionHost(context: var FusionHostContext,
      stopped: StepOutcome): HostResponse {.raises: [].} =
    ## Preserve stopped CPU/bytes; an optional extra page forces full same-code frame replacement.
    assert stopped.exit == StepExit.Host
    let expected = if context.calls < context.prelude: 42'u64 else: 43'u64
    assert uint64(stopped.hostCall) == expected
    inc context.calls
    context.trace.add(stopped.machine)
    let cpu = machineInfo(stopped.machine).value
    var memory = memoryOf(stopped.machine).value
    if context.remap and context.calls == 1:
      # The short source profile must follow the new frame while committed bytes remain intact.
      let committed = pageImage(memory, PageIndex(16))
      assert committed.error == MachineError.None
      let changed = captureMemory([committed.value,
        PageImage(index: PageIndex(18), access: PageAccess.ReadWrite)], PageLimit(3))
      assert changed.error == MachineError.None
      memory = changed.value
    HostResponse(action: HostAction.Continue, gas: cpu.gas, registers: cpu.registers,
        memory: memory)

  proc assertFusionHostTrace(actual, expected: FusionHostContext) =
    ## Every callback observes identical paid CPU and immutable memory before selecting a response.
    assert actual.calls == expected.calls and actual.trace.len == expected.trace.len
    for index in 0..<actual.trace.len:
      assertSameFusionMachine(actual.trace[index], expected.trace[index])

  proc checkFusionHostTraining(prelude: int, remap: bool, abort: bool = false,
      refuseAllocation: bool = false) =
    ## Actual prepared calls must train across short Host and replacement, or stop at the segment cap.
    let program = fusionGuest(hostPrelude = prelude)
    let runtime = newNativeRuntime()
    try:
      assert start(runtime)
    except:
      assert false, "host fusion runtime failed to start"
    let jit = newPreparedProgram(program, defaultPreparedLimits(), PvmBackend.Jit, runtime)
    let checked = newPreparedProgram(program, defaultPreparedLimits(), PvmBackend.Interpreted)
    assert jit.error == PreparationError.None and checked.error == PreparationError.None
    let memory = captureMemory([PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)],
        PageLimit(3))
    assert memory.error == MachineError.None
    var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(4000000))
    info.registers[0] = RegisterValue(165)
    info.registers[3] = RegisterValue(0xffff0000'u64)
    info.registers[5] = RegisterValue(65536)
    info.registers[6] = RegisterValue(65536)
    info.registers[12] = RegisterValue(90000)
    let source = captureMachine(program, memory.value, info)
    assert source.error == MachineError.None
    let limit = ExecutionStepLimit(2000000)
    var reference = FusionHostContext(prelude: prelude, remap: remap)
    let expected = executeWithHost(source.value, reference, continueFusionHost, limit,
      HostCallLimit(uint64(prelude+1)), checked.value)
    assert expected.error == StepError.None and expected.value.exit == StepExit.Halt
    assert reference.calls == prelude+1
    let publishes = prelude < 4095 and not abort and not refuseAllocation
    for sample in 0..2:
      # Publish the ordinary seed, train the host-separated source, then execute the actual image.
      if sample == 1:
        # Return the short Host through the public code-cache handover before a fresh CPU resumes profiling.
        when defined(pvmSharedAsyncWitness):
          if refuseAllocation: refuseNextFusionTrainingAllocation()
        let stopped = execute(source.value, limit, jit.value)
        assertSameFusionResult(stopped, execute(source.value, limit, checked.value))
        assert stopped.error == StepError.None and stopped.value.exit == StepExit.Host
        if remap:
          # A foreign program cannot consume or reinterpret the pending source profile.
          let foreign = captureMachine(fusionGuest(), memory.value, info)
          assert foreign.error == MachineError.None
          assert execute(foreign.value, limit, jit.value).error == StepError.InvalidPreparedProgram
        if abort:
          # An attempted partial prefix discards profiling and never buys another epoch-local attempt.
          assert execute(source.value, ExecutionStepLimit(1), jit.value).error ==
              StepError.StepLimitExceeded
      var context = FusionHostContext(prelude: prelude, remap: remap)
      let outcome = executeWithHost(source.value, context, continueFusionHost, limit,
        HostCallLimit(uint64(prelude+1)), jit.value)
      assertSameFusionResult(outcome, expected)
      assertFusionHostTrace(context, reference)
      waitNativeCompiler(runtime)
      let state = preparedInfo(jit.value).value
      if sample >= 1:
        if publishes:
          assert state.nativeFragments == 2, "host-separated training must publish an actual fusion image"
        else:
          assert state.nativeFragments == 1, "short host segments exhaust the bounded training window"
      if sample == 2 and publishes:
        assert state.nativeOperations > 500000, "host-separated image must execute actual source operations"
    for quota in [2'u64, 3, 4, 5, 4096, 4097]:
      # Source attempts and paid entry stay identical on both sides of the first callback.
      var actualContext = FusionHostContext(prelude: prelude, remap: remap)
      var expectedContext = FusionHostContext(prelude: prelude, remap: remap)
      let actual = executeWithHost(source.value, actualContext, continueFusionHost,
        ExecutionStepLimit(quota), HostCallLimit(uint64(prelude+1)), jit.value)
      let oracle = executeWithHost(source.value, expectedContext, continueFusionHost,
        ExecutionStepLimit(quota), HostCallLimit(uint64(prelude+1)), checked.value)
      assertSameFusionResult(actual, oracle)
      assertFusionHostTrace(actualContext, expectedContext)
    for gas in [1'u64, 3, 4, 10, 5000]:
      # Gas exhaustion before and after a real callback preserves all publicly observed prefixes.
      var cpu = info
      cpu.gas = MachineGas(gas)
      let short = captureMachine(program, memory.value, cpu)
      assert short.error == MachineError.None
      var actualContext = FusionHostContext(prelude: prelude, remap: remap)
      var expectedContext = FusionHostContext(prelude: prelude, remap: remap)
      let actual = executeWithHost(short.value, actualContext, continueFusionHost, limit,
        HostCallLimit(uint64(prelude+1)), jit.value)
      let oracle = executeWithHost(short.value, expectedContext, continueFusionHost, limit,
        HostCallLimit(uint64(prelude+1)), checked.value)
      assertSameFusionResult(actual, oracle)
      assertFusionHostTrace(actualContext, expectedContext)
    assert close(runtime)

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
    assert next == 12 and context.path[0] == 0x0201 and context.visits == 2
    assert context.gas == 90 and context.remaining == 13
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
      var cache = default(DynamicJumpTags)
      cache[0] = (1'u64 shl 32) or 11
      var dynamicRegisters = default(RegisterFile)
      dynamicRegisters[0] = RegisterValue(2)
      var dynamicContext = NativeFusionContext(gas: 100, remaining: 16, jumps: addr cache)
      let dynamicNext = enterNativeFusion(dynamicImage, 0, dynamicRegisters, dynamicContext)
      let dynamicReceipt = nativeFusionExit(blocks, 4, dynamicNext, 100, 16, dynamicContext)
      assert dynamicReceipt.valid and dynamicReceipt.paidHeader == 11 and
          dynamicReceipt.attempted == 3
      assert dynamicNext == 12 and dynamicContext.path[0] == 0x0201 and dynamicContext.visits == 2
      assert dynamicContext.gas == 90 and dynamicContext.remaining == 13
      assert uint64(dynamicRegisters[0]) == 247

when NativeReadCycleEnabled:
  proc scalarFusionCycle(count: int, conditional: bool = false): seq[NativeFusionBlock] =
    ## Literal source-independent geometry exercises arbitrary cycle lengths, prices and folded noops.
    result = newSeq[NativeFusionBlock](count)
    for index in 0..<count:
      # Each body increments the same lane; the conditional form exits exactly on its third visit.
      let header = uint32(10+index*40)
      result[index] = NativeFusionBlock(header: header, terminal: header+2,
        first: uint32(index*32), span: uint32(2+index), price: uint64(index*3),
        targets: [uint32(10+((index+1) mod count)*40), NativeEntryFailure],
        branch: NativeOperation(opcode: 40))
      result[index].operations[0] = fusionLiteralOperation([149'u8, 0x00, 1])
      if conditional:
        result[index].targets[1] = 900
        result[index].branch = NativeOperation(opcode: 81, immediate: 3)
    markNativeFusionCycles(result)

  proc checkPublicScalarFusion*(runtime: NativeRuntime, yieldAfter = false) =
    ## Ordinary prepared execution must discover the source cycle, publish it asynchronously and
    ## actually amortize native entries while matching all interpreter state and budget exits.
    ## The caller owns a started runtime with enough capacity for the primary and auxiliary.
    let program = fusionGuest(scalarOnly = true)
    let cache = newPreparedProgramCache(runtime)
    let jit = cachedPreparedProgram(cache, program, defaultPreparedLimits(), PvmBackend.Jit)
    let checked = newPreparedProgram(program, defaultPreparedLimits(), PvmBackend.Interpreted)
    assert jit.error == PreparationError.None and checked.error == PreparationError.None
    let page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
    let memory = captureMemory([page], PageLimit(2)).value
    var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000000))
    info.registers[0] = RegisterValue(165)
    info.registers[3] = RegisterValue(0xffff0000'u64)
    info.registers[5] = RegisterValue(65536)
    info.registers[12] = RegisterValue(200000)
    let source = captureMachine(program, memory, info).value
    let limit = ExecutionStepLimit(2000000)
    let expected = execute(source, limit, checked.value)
    assert expected.error == StepError.None and expected.value.exit == StepExit.Halt
    for sample in 0..2:
      # Compiler waits remain outside the public call and distinguish publication from actual use.
      let before = preparedInfo(jit.value).value
      assertSameFusionResult(execute(source, limit, jit.value), expected)
      waitNativeCompiler(runtime)
      let after = preparedInfo(jit.value).value
      if sample == 2:
        assert after.nativeFragments == 2 and after.nativeOperations-before.nativeOperations >= 1000000
        assert after.nativeCalls-before.nativeCalls < 1000, "counted cycle must amortize native entries"
    for budget in [4096'u64, 4097, 4098, 20479, 20480, 20481]:
      # These quotas straddle ordinary and compact entry horizons and original folded-noop attempts.
      let quota = ExecutionStepLimit(budget)
      assertSameFusionResult(execute(source, quota, jit.value), execute(source, quota,
          checked.value))
    info.gas = MachineGas(1000)
    let short = captureMachine(program, memory, info).value
    assertSameFusionResult(execute(short, limit, jit.value), execute(short, limit, checked.value))
    if yieldAfter:
      # Reinstalling a primary in the same source epoch must not start a second fusion window.
      let before = runtime.runtimeInfo.submitted
      yieldIdleNativeImage(cache)
      assert preparedInfo(jit.value).value.nativeCodeBytes == 0
      for sample in 0..2:
        # The shared pool has room for a second offer, so a reset epoch flag would enqueue one.
        assertSameFusionResult(execute(source, limit, jit.value), expected)
        waitNativeCompiler(runtime)
      assert preparedNativeState(jit.value).value == NativeState.Ready
      assert runtime.runtimeInfo.submitted == before+1

  proc checkFusionRetentionPressure*() =
    ## Grow a warm stream while its primary is ready and the exact hot source can offer fusion.
    let program = fusionGuest(scalarOnly = true, pressureEntry = true)
    let policy = defaultPreparedLimits()
    let checked = newPreparedProgram(program, policy, PvmBackend.Interpreted)
    assert checked.error == PreparationError.None
    let memory = captureMemory([PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)],
      PageLimit(2)).value
    var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000000))
    info.registers[0] = RegisterValue(165)
    info.registers[3] = RegisterValue(0xffff0000'u64)
    info.registers[5] = RegisterValue(65536)
    info.registers[12] = RegisterValue(200000)
    let initial = captureMachine(program, memory, info).value
    info.pc = CodeAddress(codeLength(program).value-5)
    let growth = captureMachine(program, memory, info).value
    let limit = ExecutionStepLimit(2000000)
    let expected = execute(initial, limit, checked.value)
    assert expected.error == StepError.None and expected.value.exit == StepExit.Halt
    let before = preparedInfo(checked.value).value.retainedCodePayloadBytes
    let expanded = execute(growth, limit, checked.value)
    assert expanded.error == StepError.None and expanded.value.exit == StepExit.Halt
    let after = preparedInfo(checked.value).value.retainedCodePayloadBytes
    assert after > before
    for retainGrowth in [false, true]:
      # Same source and two exact measured sizes isolate the last handback decision.
      let runtime = newNativeRuntime()
      try:
        assert start(runtime)
      except:
        assert false, "retention-pressure runtime failed to start"
      block:
        let codeBudget = newRetainedMemoryBudget(RetainedMemoryByteLimit(
          if retainGrowth: after else: before))
        let cache = newPreparedProgramCache(runtime, codeBudget = codeBudget)
        let jit = cachedPreparedProgram(cache, program, policy, PvmBackend.Jit)
        assert jit.error == PreparationError.None
        assertSameFusionResult(execute(initial, limit, jit.value), expected)
        assert preparedInfo(jit.value).value.retainedCodePayloadBytes == before
        assert runtime.runtimeInfo.submitted == 1
        waitNativeCompiler(runtime)
        assertSameFusionResult(execute(growth, limit, jit.value), expanded)
        if retainGrowth:
          # The accepted handback queues the real graph, which must execute on the next call.
          assert runtime.runtimeInfo.submitted == 2
          waitNativeCompiler(runtime)
          let admitted = preparedInfo(jit.value).value
          assert admitted.retainedCodePayloadBytes == after
          assertSameFusionResult(execute(growth, limit, jit.value), expanded)
          let completed = preparedInfo(jit.value).value
          assert completed.nativeFragments == 2
          assert completed.nativeOperations-admitted.nativeOperations >= 1000000
        else:
          # A refused handback never acquires an auxiliary credit or loses the completed result.
          assert runtime.runtimeInfo.submitted == 1
          assert preparedInfo(jit.value).value.streamNodes == 0
          assert runtime.runtimeInfo.registered == 0
      assert close(runtime)

  proc checkScalarFusionCycles() =
    ## Compare both native lowerers against independent visit/debit equations, including rotation,
    ## zero price, short gas/quota, exact horizon, side exits and unwritten path bytes.
    for count in 1..NativeFusionCycleLimit:
      for conditional in [false, true]:
        let blocks = scalarFusionCycle(count, conditional)
        let image = lowerNativeFusion(blocks)
        assert image.ready
        for entry in 0..<count:
          assert blocks[entry].cycleSize == uint8(count)
          assert nativeFusionDispatchEntry(image, entry)
          for gasLimited in [false, true]:
            for budget in [0'u64, 1, 2, 3, 8, 31, 63, 64, 65, 4095, 4096, 4097, 1000000]:
              # Compute the ordered original reservations without consulting any returned native receipt.
              let gas = if gasLimited: budget else: 1000000'u64
              let quota = if gasLimited: 1000000'u64 else: budget
              var leftGas = gas
              var leftQuota = quota
              var position = entry
              var visits = 0'u64
              var next = blocks[entry].header
              while visits < uint64(NativeFusionCycleVisitLimit):
                let item = blocks[position]
                if leftGas < item.price or leftQuota < uint64(item.span): break
                leftGas -= item.price
                leftQuota -= uint64(item.span)
                inc visits
                if conditional and visits == 3:
                  next = 900
                  break
                position = (position+1) mod count
                next = blocks[position].header
              var registers = default(RegisterFile)
              var context = NativeFusionContext(gas: gas, remaining: quota)
              for index in 0..<context.path.len: context.path[index] = high(uint64)
              assert enterNativeFusion(image, entry, registers, context) == next
              assert context.visits == visits and context.paid == 0
              assert context.gas == leftGas and context.remaining == leftQuota
              assert uint64(registers[0]) == visits
              for word in context.path: assert word == high(uint64), "compact entries never log a path"
              let receipt = nativeFusionCycleExit(blocks, uint32(entry+1), next, gas, quota, context)
              assert receipt.valid and receipt.attempted == uint32(quota-leftQuota)
              if visits != 0:
                assert receipt.lastToken == uint32((entry+int(visits)-1) mod count+1)
                assert receipt.branches and receipt.paidHeader == 0
              assert not nativeFusionCycleExit(blocks, uint32(entry+1), next+1, gas, quota, context).valid
              context.paid = 1
              assert not nativeFusionCycleExit(blocks, uint32(entry+1), next, gas, quota, context).valid
              context.paid = 0
              inc context.remaining
              assert not nativeFusionCycleExit(blocks, uint32(entry+1), next, gas, quota, context).valid

    # Every guest lane participates so x86 must keep both GPR and SSE2 placements across cyclic links.
    var banked = scalarFusionCycle(3)
    for index in 0..<banked.len:
      banked[index].terminal = banked[index].header+14
      banked[index].span = 14
      for lane in 0..12:
        banked[index].operations[lane] = fusionLiteralOperation([149'u8, byte(lane*17), byte(lane+1)])
    markNativeFusionCycles(banked)
    let bankedImage = lowerNativeFusion(banked)
    assert bankedImage.ready
    for entry in 0..<banked.len:
      var registers = default(RegisterFile)
      for lane in 0..12: registers[lane] = RegisterValue(high(uint64)-uint64(lane))
      var context = NativeFusionContext(gas: 1000000, remaining: 1000000)
      let next = enterNativeFusion(bankedImage, entry, registers, context)
      assert context.visits == uint64(NativeFusionCycleVisitLimit)
      for lane in 0..12:
        assert uint64(registers[lane]) == high(uint64)-uint64(lane) +
          uint64(NativeFusionCycleVisitLimit)*uint64(lane+1)
      assert nativeFusionCycleExit(banked, uint32(entry+1), next, 1000000, 1000000, context).valid

    # An SCC with two in-cycle choices is not a deterministic compact cycle, even with a small subcycle.
    var branching = scalarFusionCycle(3)
    branching[0].targets[1] = branching[2].header
    branching[0].branch = NativeOperation(opcode: 81)
    markNativeFusionCycles(branching)
    for item in branching: assert item.cycleNext == 0 and item.cycleSize == 0
    var wide = scalarFusionCycle(NativeFusionCycleLimit+1)
    for item in wide: assert item.cycleNext == 0 and item.cycleSize == 0

    # A memory guard breaks scalar eligibility; false annotations cannot authorize a published image.
    var guarded = scalarFusionCycle(3)
    guarded[1].operations[0] = fusionLiteralOperation([128'u8, 0x10, 0])
    guarded[1].guards = 1
    assert not lowerNativeFusion(guarded).ready
    markNativeFusionCycles(guarded)
    for item in guarded: assert item.cycleNext == 0
    var forged = scalarFusionCycle(3)
    forged[0].cycleNext = forged[0].cycleNext+1
    assert not lowerNativeFusion(forged).ready

    # Compact side exits return checked; outside native paths retain ordinary links through the cycle.
    var mixed = scalarFusionCycle(3, true)
    mixed.add(NativeFusionBlock(header: 900, terminal: 902, first: 200, span: 2, price: 7,
      guards: 1,
      targets: [10'u32, NativeEntryFailure], branch: NativeOperation(opcode: 40)))
    mixed[3].operations[0] = fusionLiteralOperation([124'u8, 0x41, 0])
    markNativeFusionCycles(mixed)
    assert mixed[0].cycleSize == 3 and mixed[3].cycleSize == 0
    let mixedImage = lowerNativeFusion(mixed)
    assert mixedImage.ready
    var bytes = [42'u8]
    var mixedRegisters = default(RegisterFile)
    mixedRegisters[4] = RegisterValue(65536)
    var mixedContext = NativeFusionContext(gas: 1000, remaining: 1000)
    assert enterNativeFusion(mixedImage, 0, mixedRegisters, mixedContext) == 900
    assert mixedContext.visits == 3 and mixedContext.paid == 0
    assert nativeFusionCycleExit(mixed, 1, 900, 1000, 1000, mixedContext).valid
    mixedContext.memory.read[0] = initNativeReadRegion(65536, bytes)
    let beforeGas = mixedContext.gas
    let beforeQuota = mixedContext.remaining
    assert enterNativeFusion(mixedImage, 3, mixedRegisters, mixedContext) == 10
    assert mixedContext.visits == uint64(NativeFusionVisitLimit) and (mixedContext.path[0] and
        255) == 4
    assert nativeFusionExit(mixed, 900, 10, beforeGas, beforeQuota, mixedContext).valid

    # A live dynamic tag enters the ordinary logged continuation, preserving its original path coverage.
    mixed[0].indirectEntry = true
    mixed[3].terminal = 901
    mixed[3].span = 1
    mixed[3].guards = 0
    mixed[3].targets = [NativeEntryFailure, NativeEntryFailure]
    mixed[3].branch = NativeOperation(opcode: 50)
    markNativeFusionCycles(mixed)
    let indirectImage = lowerNativeFusion(mixed)
    assert indirectImage.ready
    var jumps = default(DynamicJumpTags)
    jumps[0] = (1'u64 shl 32) or 11
    mixedRegisters[0] = RegisterValue(2)
    mixedContext = NativeFusionContext(gas: 1000, remaining: 1000, jumps: addr jumps)
    assert enterNativeFusion(indirectImage, 3, mixedRegisters, mixedContext) == 901
    assert mixedContext.paid == 1 and mixedContext.visits == 3 and mixedContext.path[0] == 0x040104
    assert uint64(mixedRegisters[0]) == 3
    assert nativeFusionExit(mixed, 900, 901, 1000, 1000, mixedContext).valid

    # Metadata queries remain bounded and moved/default images expose no compact selection.
    var empty = default(NativeImage)
    assert not nativeFusionCycleEntry(empty, 0)
    var transferable = lowerNativeFusion(scalarFusionCycle(1))
    assert nativeFusionCycleEntry(transferable, 0)
    assert not nativeFusionCycleEntry(transferable, -1)
    assert not nativeFusionCycleEntry(transferable, NativeFusionBlockLimit)
    let retained = move(transferable)
    assert nativeFusionCycleEntry(retained, 0)
    assert not nativeFusionCycleEntry(transferable, 0)

    # A full ordinary arena can retain only some optional duplicates. Refused copies keep callable
    # logged entries, rather than disabling an otherwise valid graph or publishing a partial cycle.
    var crowded = newSeq[NativeFusionBlock](NativeFusionBlockLimit)
    for index in 0..<crowded.len:
      let header = uint32(index*40)
      crowded[index] = NativeFusionBlock(header: header, terminal: header+32,
        first: uint32(index*32), span: 32, price: 1,
        targets: [header, NativeEntryFailure], branch: NativeOperation(opcode: 40))
      for position in 0..<31:
        crowded[index].operations[position] = NativeOperation(opcode: 20,
          immediate: 0x123456789abcdef0'u64)
    markNativeFusionCycles(crowded)
    let crowdedImage = lowerNativeFusion(crowded)
    assert crowdedImage.ready and crowdedImage.codeBytes <= uint64(NativeFusionImageLimit)
    var duplicates = 0
    var ordinary = -1
    for index in 0..<crowded.len:
      assert nativeFusionEntry(crowdedImage, index)
      if nativeFusionCycleEntry(crowdedImage, index): inc duplicates
      else: ordinary = index
    assert duplicates > 0 and duplicates < crowded.len and ordinary >= 0
    var ordinaryRegisters = default(RegisterFile)
    var ordinaryContext = NativeFusionContext(gas: 1000000, remaining: 1000000)
    let ordinaryNext = enterNativeFusion(crowdedImage, ordinary, ordinaryRegisters, ordinaryContext)
    assert ordinaryNext == crowded[ordinary].header
    assert ordinaryContext.visits == uint64(NativeFusionVisitLimit)
    assert nativeFusionExit(crowded, crowded[ordinary].header, ordinaryNext, 1000000, 1000000,
      ordinaryContext).valid

    # Huge prices and zero-priced members retain guarded subtraction at the full unsigned boundary.
    var expensive = scalarFusionCycle(3)
    expensive[0].price = high(uint64)
    let costly = lowerNativeFusion(expensive)
    assert costly.ready
    var registers = default(RegisterFile)
    var context = NativeFusionContext(gas: high(uint64), remaining: high(uint64))
    let next = enterNativeFusion(costly, 0, registers, context)
    assert context.visits == 1 and context.gas == 0 and context.remaining == high(uint64)-2
    assert next == expensive[1].header
    assert nativeFusionCycleExit(expensive, 1, next, high(uint64), high(uint64), context).valid
    context.visits = uint64(NativeFusionCycleVisitLimit)+1
    assert not nativeFusionCycleExit(expensive, 1, next, high(uint64), high(uint64), context).valid

proc checkWindowFusionFault()
  ## The grouped ordinary-call fault/repair witness is defined after the public fusion checks.

proc checkLateFusionFault(wide: bool)
  ## The late paid-memory fixture is defined below the main supported fusion witness.

proc checkPublicFusion(mode: byte, conditional: bool = false) =
  ## Every source-backed branch form must preserve complete CPU/memory state and paid accounting.
  let program = fusionGuest(mode = mode, conditional = conditional)
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
  var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(4000000))
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
      let span = (if mode == 181: 8'u64 else: 7'u64)+(if conditional: 4'u64 else: 0'u64)
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
    info.gas = MachineGas(4000000)
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
  info.gas = MachineGas(4000000)
  info.registers[6] = RegisterValue(69632)
  let missing = captureMachine(program, memory, info).value
  let beforeFault = preparedInfo(jit.value).value.nativeOperations
  let fault = execute(missing, limit, jit.value)
  assert preparedInfo(jit.value).value.nativeOperations == beforeFault+4, "native paid prefix"
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
  runMemoryWindows()
  checkRepeatedFusionReceipt()
  checkCollidingFusionReceipts()
  checkLongFusionReceipts()
  when NativeReadCycleEnabled:
    checkScalarFusionCycles()
    block:
      # Qualify ordinary scalar fusion on a fresh runtime with no competing resident owners.
      let runtime = newNativeRuntime()
      try:
        assert start(runtime)
      except:
        assert false, "scalar fusion runtime failed to start"
      checkPublicScalarFusion(runtime)
      assert close(runtime)
    when defined(pvmSharedAsyncWitness): runFusionComposition()
    checkFusionConditionalMoves()
    checkFusionGraphTokens()
    checkFusionIndirectTargets()
    checkDenseFusionGuards()
    checkShortFusionEntries()
    checkFusionHostTraining(1, false)
    checkFusionHostTraining(1, true)
    checkFusionHostTraining(4094, false)
    checkFusionHostTraining(4095, false)
    checkFusionHostTraining(1, false, abort = true)
    when defined(pvmSharedAsyncWitness):
      checkFusionHostTraining(1, false, refuseAllocation = true)
  for mode in [0'u8, 50, 180, 181]:
    checkPublicFusion(mode)
  checkPublicFusion(0, conditional = true)
  checkWindowFusionFault()
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

proc checkWindowFusionFault() =
  ## Train one source-owned graph, preserve a late partial read, then repair and resume the same owners.
  let program = fusionGuest(windows = true)
  let runtime = newNativeRuntime()
  try:
    assert start(runtime)
  except:
    assert false, "memory-window runtime failed to start"
  let jit = newPreparedProgram(program, defaultPreparedLimits(), PvmBackend.Jit, runtime)
  let checked = newPreparedProgram(program, defaultPreparedLimits(), PvmBackend.Interpreted)
  assert jit.error == PreparationError.None and checked.error == PreparationError.None
  var page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
  for index in 0..<page.bytes.len: page.bytes[index] = byte(index and 255)
  let capturedMemory = captureMemory([page], PageLimit(2))
  assert capturedMemory.error == MachineError.None
  let memory = capturedMemory.value
  var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(8000000))
  info.registers[0] = RegisterValue(0xdeadbeef000000a5'u64)
  info.registers[3] = RegisterValue(0xffff0000'u64)
  info.registers[5] = RegisterValue(65536)
  info.registers[6] = RegisterValue(65536)
  info.registers[7] = RegisterValue(0x8765432100000007'u64)
  info.registers[12] = RegisterValue(90000)
  let captured = captureMachine(program, memory, info)
  assert captured.error == MachineError.None
  let source = captured.value
  let limit = ExecutionStepLimit(2000000)
  let expected = execute(source, limit, checked.value)
  assert expected.error == StepError.None and expected.value.exit == StepExit.Halt
  for sample in 0..2:
    # Publish/train outside invocation; every process call retains its full scalar state oracle.
    assertSameFusionResult(execute(source, limit, jit.value), expected)
    waitNativeCompiler(runtime)
  assert preparedInfo(jit.value).value.nativeFragments == 2
  info.registers[6] = RegisterValue(65536+4096-12)
  let late = captureMachine(program, memory, info)
  assert late.error == MachineError.None
  let before = preparedInfo(jit.value).value.nativeOperations
  let fault = execute(late.value, limit, jit.value)
  let reference = execute(late.value, limit, checked.value)
  assertSameFusionResult(fault, reference)
  assert fault.error == StepError.None and fault.value.exit == StepExit.Fault
  assert preparedInfo(jit.value).value.nativeOperations > before
  let cpu = machineInfo(fault.value.machine).value
  assert uint64(cpu.registers[2]) == 3 and cpu.blockCharged
  assert uint64(cpu.registers[1]) == 0xfffffffffffff8f7'u64,
    "checked replay must retain the first signed read before the second read faults"
  assert uint64(fault.value.faultPage) == 17'u64*4096
  assert pageImage(memory, PageIndex(16)).value == page
  assert machineInfo(late.value).value == info
  let committed = pageImage(memoryOf(fault.value.machine).value, PageIndex(16)).value
  let repairedMemory = captureMemory([committed,
    PageImage(index: PageIndex(17), access: PageAccess.ReadWrite)], PageLimit(2))
  assert repairedMemory.error == MachineError.None
  let repaired = captureMachine(program, repairedMemory.value, cpu)
  assert repaired.error == MachineError.None
  let resumed = execute(repaired.value, limit, jit.value)
  let resumedReference = execute(repaired.value, limit, checked.value)
  assertSameFusionResult(resumed, resumedReference)
  assert resumed.error == StepError.None and resumed.value.exit == StepExit.Halt
  assert close(runtime)
