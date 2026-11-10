# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise both native lowerers against the same register, memory, and budget checkpoints.

import std/[assertions, syncio]
import ../../src/pvm/[machine, program]
import ../../src/pvm/internal/[native_ir, native_platform, native_read_body, native_read_cycle]
when defined(pvmReadCycleCreditWitness) and defined(pvmX86Jit) and NativeReadCycleEnabled:
  import ../../src/pvm/internal/x86_jit
when NativeReadCycleEnabled and defined(pvmSharedAsyncWitness):
  import ../../src/pvm/internal/native_pipeline

when NativeReadCycleEnabled:
  when defined(pvmReadCycleCreditWitness):
    proc hasCreditReservation(image: openArray[byte]): bool =
      ## Match the R9 minimum of the gas and quota credits in the emitted entry setup.
      const signature = [0x49'u8, 0x89, 0xc9, 0x49, 0x89, 0xd0,
        0x49, 0xc1, 0xe9, 7, 0x49, 0xc1, 0xe8, 5, 0x4d, 0x39, 0xc1,
        0x4d, 0x0f, 0x47, 0xc8]
      if image.len < signature.len: return false
      for offset in 0..image.len-signature.len:
        # A complete contiguous signature identifies the credit setup instead of a single opcode.
        var equal = true
        for index in 0..<signature.len:
          if image[offset+index] != signature[index]:
            equal = false
            break
        if equal: return true
      false

  const
    wordAddress = 0x11000'u64
    tailAddress = 0x12000'u64
    readHeader = 10'u32
    setupHeader = 40'u32
    tailHeader = 60'u32
    layout = NativeCycleLayout(sites: [
      NativeCycleSite(header: readHeader, first: 1, price: 60),
      NativeCycleSite(header: setupHeader, price: 3),
      NativeCycleSite(header: 50, price: 7),
      NativeCycleSite(header: tailHeader, price: 11),
      NativeCycleSite(header: 70, price: 13),
      NativeCycleSite(header: 80, price: 3),
      NativeCycleSite(header: 90, price: 1)], outsideHeader: 100)

  proc operation(opcode, lanes: byte, operand: uint32 = 0): NativeOperation =
    ## Decode genuine slots from a single instruction followed by the checked halt.
    let wire = [0'u8, 0, 7, opcode, lanes, byte(operand and 255),
      byte((operand shr 8) and 255), byte((operand shr 16) and 255), byte(operand shr 24),
      0, 0x41]
    let owner = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
    assert owner.error == ProgramError.None, "decode literal operation wire"
    let decoded = instruction(owner.value, CodeAddress(0))
    assert decoded.error == ProgramError.None, "recover literal operation slots"
    NativeOperation(opcode: opcode, slots: instructionRegisters(decoded),
      immediate: uint64(decoded.value.x))

  proc readFixture(overlap: bool, epoch: uint64): NativeReadBody =
    ## Build the original paid Read without attaching the optional setup block.
    result = initNativeReadBody(readHeader, 33, 1, 24, epoch)
    # The overlap case must use the old r6 address before replacing it with the loaded byte.
    let firstLoad = operation(124, if overlap: 0x66'u8 else: 0x36'u8)
    let qwordLoad = operation(130, if overlap: 0xa7'u8 else: 0x37'u8)
    let body = [
      firstLoad, operation(151, 0xb7), qwordLoad,
      operation(200, 0xbb, 7), operation(129, 0xa7), operation(51, 7),
      operation(151, 0xb7), operation(152, 0xb7), operation(130, 0xa7),
      operation(198, 0xbb, 7), operation(132, 0xb7), operation(198, 0xbb, 7),
      operation(130, 0xa7), operation(197, 0xbb, 7), operation(212, 0xbb, 7),
      operation(151, 0xb7), operation(152, 0xb7), operation(130, 0xa7),
      operation(198, 0xbb, 7), operation(130, 0xa7), operation(197, 0xbb, 7),
      operation(212, 0xbb, 7)]
    for i, op in body:
      # The leading noop folds into the header. The 22 read operations follow it in order.
      let offset = uint32(i)+1
      assert addReadBodyOperation(result, readHeader+offset, 1+offset, op),
        "append one source Read operation"

  proc cycleFixture(overlap = false, outside = false, receiptLayout = layout,
      epoch = 1'u64): NativeReadCycle =
    ## Extend the same paid Read with setup and the certified connected route.
    var read = readFixture(overlap, epoch)
    let outerUpdate = if overlap: operation(149, 0x36) else: operation(149, 0x88, 2)
    let setup = [operation(51, 9, 0x7a), operation(200, 0xb9, 9), operation(149, 0x99, 2)]
    assert addNativeReadContinuation(read,
      NativeReadContinuation(header: setupHeader, terminal: 44, price: 3), setup), "append complete StoreSetup"
    let outerBranch = operation(81, 0x48, if outside: 3'u32 else: 0'u32)
    NativeReadCycle(read: read, layout: receiptLayout,
      word: NativeCycleWord(valueLane: 0, shiftLane: 1, byteLane: 2, baseLane: 3, boundLane: 4),
      tailLoad: operation(57, 5, uint32(tailAddress)),
      tailStep: operation(131, 0x55, 1), tailBranch: operation(173, 0xc5),
      outer: [operation(131, 0x88, 1), outerUpdate, outerBranch],
      gate: operation(88, 0x4a))

  type ReadExit {.pure.} = enum ## Which checkpoint the literal path reaches.
    UnpaidTail, LaterMiss, FirstMiss, Overlap, UnpaidStore, Outside

  proc checkEntry(image: NativeImage, tailReadable: bool, gas, remaining: uint64,
      expectedHeader: uint32, expectedGas, expectedRemaining: uint64, exit: ReadExit,
      receiptLayout = layout, pageDirty = true, expectedImage: openArray[byte] = [],
      storeAddress = wordAddress, trailingDirty = false, bitmapWords = 1'u64) =
    ## Compare each entire register/memory checkpoint and the receipt after real machine code.
    var registers = default(RegisterFile)
    for i in 0..<registers.len:
      # Distinct upper halves detect incorrect sign extension and clobbered lanes.
      registers[i] = RegisterValue(0x1234567800000000'u64+uint64(i))
    registers[0] = RegisterValue(0x1122334487665544'u64)
    registers[1] = RegisterValue(0)
    registers[3] = RegisterValue(wordAddress)
    registers[4] = RegisterValue(wordAddress+4)
    registers[8] = RegisterValue(0x7fffffff)
    registers[10] = RegisterValue(tailAddress+4)
    registers[11] = RegisterValue(0)
    registers[12] = RegisterValue(0xfffffffffffffffe'u64)

    if exit == ReadExit.Overlap: registers[6] = RegisterValue(wordAddress)
    if exit == ReadExit.Outside: registers[8] = RegisterValue(0)

    var expected = registers
    var visits = default(NativeCycleVisits)
    var last = NativeCycleNoCompleted
    const original = [0x19'u8, 0x2a, 0x3b, 0x4c, 0x6e, 0x7f, 0x80, 0x91]
    var expectedMemory = original
    if exit != ReadExit.FirstMiss:
      # Every successful first Read reaches and commits Setup in these fixtures.
      expected[6] = RegisterValue(0x19)
      expected[7] = RegisterValue(0)
      expected[9] = RegisterValue(0x7c)
      visits = [1'u64, 1, 0, 0, 0, 0, 0]
      last = uint64(ord(NativeCycleRole.StoreSetup))
      if exit != ReadExit.UnpaidStore:
        # A committed Store publishes its four bytes and the canonical loop state.
        expected[1] = RegisterValue(32)
        expected[2] = RegisterValue(0x87)
        expected[3] = RegisterValue(wordAddress+4)
        expectedMemory = [0x44'u8, 0x55, 0x66, 0x87, 0x6e, 0x7f, 0x80, 0x91]
        visits[NativeCycleRole.Store] = 1
        last = uint64(ord(NativeCycleRole.Store))
    if exit in {ReadExit.LaterMiss, ReadExit.Overlap, ReadExit.Outside}:
      # Tail, Jump and Outer commit before the later Read or the outside exit.
      expected[5] = RegisterValue(high(uint64))
      expected[8] = RegisterValue(0xffffffff80000002'u64)
      visits = [1'u64, 1, 1, 1, 1, 1, 1]
      last = uint64(ord(NativeCycleRole.Gate))
    if exit == ReadExit.Outside:
      # The exact Outer branch leaves the region without executing Gate.
      expected[8] = RegisterValue(3)
      visits[NativeCycleRole.Gate] = 0
      last = uint64(ord(NativeCycleRole.Outer))
    if exit == ReadExit.Overlap:
      # Outer updated r6 to the post-Store base. A stale r6 would make the later Read miss.
      expected[6] = RegisterValue(0x6e)
      expected[8] = RegisterValue(0xffffffff80000000'u64)
      visits[NativeCycleRole.Read] = 2
      last = uint64(ord(NativeCycleRole.Read))

    var writable = original
    let readable = [0xfe'u8, 0xff, 0xff, 0xff, 0x80, 0x21, 0x32, 0x43, 0x54, 0x65, 0x76, 0x87]
    let firstPage = storeAddress shr 12
    let lastPage = (storeAddress+3) shr 12
    var initialDirty = default(array[2, uint64])
    if pageDirty:
      initialDirty[int(firstPage shr 6)] = 1'u64 shl (firstPage and 63)
    if trailingDirty:
      initialDirty[int(lastPage shr 6)] = initialDirty[int(lastPage shr 6)] or
        (1'u64 shl (lastPage and 63))
    var dirty = initialDirty
    let readableRegion =
      if tailReadable: initNativeReadRegion(tailAddress, readable)
      else: initNativeReadRegion(tailAddress+4, readable.toOpenArray(4, 11))
    let wordReadable =
      if exit == ReadExit.FirstMiss: initNativeReadRegion(wordAddress, writable.toOpenArray(0, 6))
      else: initNativeReadRegion(wordAddress, writable)
    var context = NativeCycleContext(
      read: [default(NativeReadRegion), wordReadable, readableRegion],
      writable: [NativeCycleWritable(first: max(0x13000'u64, storeAddress+8)),
        NativeCycleWritable(first: storeAddress, length: uint64(writable.len),
          data: cast[pointer](addr writable[0]))],
      dirty: cast[pointer](addr dirty[0]), dirtyWords: bitmapWords, gas: gas, remaining: remaining,
      visits: [2'u64, 3, 4, 5, 6, 7, 8], lastCompleted: 9, paidRead: 9)
    let destination =
      when defined(pvmReadCycleCreditWitness):
        if expectedImage.len > 0:
          enterNativeReadCycleAbiProof(image, registers, context, expectedImage)
        else:
          # Other shared entry cases keep their normal SysV witness.
          enterNativeReadCycleAbiProof(image, registers, context)
      elif defined(pvmX86Jit) and defined(pvmX86ResidentProof):
        enterNativeReadCycleAbiProof(image, registers, context)
      else:
        enterNativeReadCycle(image, registers, context)
    let paidRead = exit == ReadExit.FirstMiss or exit == ReadExit.LaterMiss
    assert destination == expectedHeader, "resume at the expected checked header"
    assert context.gas == expectedGas and context.remaining == expectedRemaining,
      "publish only consumed gas and attempts"
    assert context.visits == visits and context.lastCompleted == last and
      context.paidRead == uint64(ord(paidRead)), "publish the completed path and paid Read flag"
    assert validNativeCycleReceipt(receiptLayout, destination, gas, remaining, context),
      "accept the receipt at the checked boundary"
    assert registers == expected, "preserve each committed lane and discard speculative lanes"
    assert writable == expectedMemory, "publish only the committed Store bytes"
    assert dirty == initialDirty, "preserve the pre-existing dirty bitmap"
    when defined(pvmReadCycleRoleWitness) and not defined(pvmReadCycleCreditWitness):
      # Keep the inherited boundary results visible in both prototype profiles.
      echo "READ_CYCLE_ROLE_LEGACY,", gas, ",", remaining, ",", destination, ",", context.gas, ",",
        context.remaining, ",", context.lastCompleted, ",", context.paidRead, ",",
        context.visits[NativeCycleRole.Store]

  when defined(pvmReadCycleRoleWitness) and defined(pvmX86ResidentProof):
    proc roleFixture(extraWrites: range[0..2], outside: bool): NativeReadCycle =
      ## Five Read destinations plus distinct base r3 fill the SysV bank.
      ## Extra Read destinations force the resident-budget and stack fallbacks.
      result = cycleFixture()
      result.read = initNativeReadBody(readHeader, 33, 1, 24, 1)
      for index in 0..<22:
        let op = case index
          of 0: operation(124, 0x36)  # r6 = byte[r3], including the mapped base.
          of 1: operation(51, 9, 17)
          of 2: operation(51, if extraWrites >= 1: 0'u8 else: 7'u8, 23)
          of 3: operation(51, if extraWrites == 2: 8'u8 else: 7'u8, 29)
          of 19: operation(51, 6, 0x87665544'u32)
          of 20: operation(129, 0xba) # r10 = i32[r11], the late guard.
          of 21: operation(51, 11, 0x2468)
          else: operation(51, 7, 0)
        let offset = uint32(index)+1
        assert addReadBodyOperation(result.read, readHeader+offset, 1+offset, op)
      # Setup uses mapped r3 to compute r10 = r3+r5+1, then aliases r10 in place.
      let setup = [operation(51, 7), operation(200, 0x53, 10), operation(149, 0xaa, 1)]
      assert addNativeReadContinuation(result.read,
        NativeReadContinuation(header: setupHeader, terminal: 44, price: 3), setup)
      result.word = NativeCycleWord(valueLane: 6, shiftLane: 7, byteLane: 9,
        baseLane: 3, boundLane: 10)
      result.tailLoad = operation(57, 9, uint32(tailAddress))
      result.tailStep = operation(131, 0x99, 1)
      result.tailBranch = operation(173, 0x97) # r7 <s r9, false after the signed Tail update.
      result.outer = [operation(131, 0x66, 1), operation(149, 0x3b, 16),
        operation(81, 0x4b, if outside: uint32(wordAddress+24) else: 0'u32)]
      # The comparison becomes false only after Outer increments the mapped r6.
      result.gate = operation(88, 0x46, 0x87665544'u32)

    type RoleExit {.pure.} = enum
      ## Exact checkpoint after zero, one, or two completed Store groups.
      FirstMiss, StoreGas, StoreAttempts, TailPreflight, Outside, ReadGas, LaterMiss

    proc checkRoleEntry(cycle: NativeReadCycle, image: NativeImage, extraWrites: range[0..2],
        exit: RoleExit, quotaRefill = false) =
      ## Assert all lanes and memory after a real SysV call against a literal oracle.
      let (gas, remaining, header, finalGas, finalRemaining) = case exit
        of RoleExit.FirstMiss: (0'u64, 0'u64, readHeader, 0'u64, 0'u64)
        of RoleExit.StoreGas: (31'u64, 1000'u64, 50'u32, 0'u64, 976'u64)
        of RoleExit.StoreAttempts: (1000'u64, 43'u64, 50'u32, 969'u64, 19'u64)
        of RoleExit.TailPreflight: (1000'u64, 1000'u64, tailHeader, 941'u64, 956'u64)
        of RoleExit.Outside: (1000'u64, 1000'u64, 100'u32, 914'u64, 948'u64)
        of RoleExit.ReadGas: (146'u64, 1000'u64, readHeader, 59'u64, 947'u64)
        of RoleExit.LaterMiss: (1000'u64, 1000'u64, readHeader, 853'u64, 923'u64)
      assert not quotaRefill or exit == RoleExit.LaterMiss
      # Two initial quota credits cannot cover this paid path. The later paid miss consumes 77.
      let available = if quotaRefill: 77'u64 else: remaining
      let expectedQuota = if quotaRefill: 0'u64 else: finalRemaining
      var registers = default(RegisterFile)
      for slot in 0..<registers.len:
        registers[slot] = RegisterValue(0x1234567800000000'u64+uint64(slot))
      registers[3] = RegisterValue(wordAddress)
      registers[5] = RegisterValue(7)
      let tailOffset = if exit == RoleExit.FirstMiss: 12'u64 else: 4'u64
      registers[11] = RegisterValue(tailAddress+tailOffset)
      var expected = registers
      const original = [0x19'u8, 0x2a, 0x3b, 0x4c, 0x6e, 0x7f, 0x80, 0x91,
        0xaa, 0xbb, 0xcc, 0xdd, 0x50, 0x61, 0x72, 0x83]
      var writable = original
      var expectedMemory = original
      var visits = default(NativeCycleVisits)
      var last = NativeCycleNoCompleted
      if exit != RoleExit.FirstMiss:
        # The first Store group's original successor is Store, even on unpaid exit.
        let groups = if exit in {RoleExit.StoreGas, RoleExit.StoreAttempts}: 1 else: 2
        visits = [1'u64, 1, uint64(groups), 0, 0, 0, 0]
        last = uint64(ord(NativeCycleRole.Store))
        expected[3] = RegisterValue(wordAddress+uint64(groups)*4)
        expected[6] = RegisterValue(0xffffffff87665544'u64)
        expected[7] = RegisterValue(uint64(groups)*32)
        expected[9] = RegisterValue(0x87)
        expected[10] = RegisterValue(wordAddress+8)
        expected[11] = RegisterValue(0x2468)
        if extraWrites >= 1: expected[0] = RegisterValue(23)
        if extraWrites == 2: expected[8] = RegisterValue(29)
        for index in 0..<groups:
          let base = 4*index
          expectedMemory[base] = 0x44
          expectedMemory[base+1] = 0x55
          expectedMemory[base+2] = 0x66
          expectedMemory[base+3] = 0x87
      if exit in {RoleExit.Outside, RoleExit.ReadGas, RoleExit.LaterMiss}:
        # Mapped Tail and Outer writes reach their predicates and the caller.
        expected[6] = RegisterValue(0xffffffff87665545'u64)
        expected[9] = RegisterValue(high(uint64))
        expected[11] = RegisterValue(wordAddress+24)
        visits = [1'u64, 1, 2, 1, 1, 1, uint64(ord(exit != RoleExit.Outside))]
        let role = if exit == RoleExit.Outside: NativeCycleRole.Outer else: NativeCycleRole.Gate
        last = uint64(ord(role))
      const readOnly = [0xfe'u8, 0xff, 0xff, 0xff, 0x2a, 0, 0, 0]
      let readable = if exit == RoleExit.TailPreflight:
          initNativeReadRegion(tailAddress+4, readOnly.toOpenArray(4, 7))
        else: initNativeReadRegion(tailAddress, readOnly)
      const initialDirty = 1'u64 shl (wordAddress shr 12)
      var dirty = initialDirty
      var context = NativeCycleContext(
        read: [default(NativeReadRegion), initNativeReadRegion(wordAddress, writable), readable],
        writable: [NativeCycleWritable(first: 0x13000),
          NativeCycleWritable(first: wordAddress, length: uint64(writable.len),
            data: cast[pointer](addr writable[0]))],
        dirty: cast[pointer](addr dirty), dirtyWords: 1, gas: gas, remaining: available,
        visits: [2'u64, 3, 4, 5, 6, 7, 8], lastCompleted: 9, paidRead: 9)
      let destination =
        when defined(pvmReadCycleCreditWitness):
          let expectedImage = x86ReadCycleInstructions(cycle)
          assert hasCreditReservation(expectedImage) == (extraWrites == 0),
            "credit selection must match the eligible role bank"
          enterNativeReadCycleAbiProof(image, registers, context, expectedImage)
        else:
          enterNativeReadCycleAbiProof(image, registers, context)
      let paid = uint64(ord(exit in {RoleExit.FirstMiss, RoleExit.LaterMiss}))
      assert destination == header and
        context.gas == finalGas and context.remaining == expectedQuota
      assert context.visits == visits and context.lastCompleted == last and context.paidRead == paid
      assert validNativeCycleReceipt(cycle.layout, destination, gas, available, context)
      if last != NativeCycleNoCompleted:
        assert nativeCycleSuccessor(cycle, NativeCycleRole(last), registers) == destination
      assert registers == expected and writable == expectedMemory and dirty == initialDirty
      when not defined(pvmReadCycleCreditWitness):
        echo "READ_CYCLE_ROLE,", extraWrites, ",", ord(exit), ",", destination, ",",
          context.gas, ",", context.remaining, ",", context.visits[NativeCycleRole.Store], ",", paid

    proc runReadCycleRoleWitness() =
      ## Exercise all three capacities through the real published-image entry.
      for extra in 0..2:
        let cycle = roleFixture(extra, false)
        let outside = roleFixture(extra, true)
        var image = lowerNativeReadCycle(cycle)
        var outsideImage = lowerNativeReadCycle(outside)
        assert image.ready and image.kind == NativeKind.ConnectedReadCycle
        assert outsideImage.ready and outsideImage.kind == NativeKind.ConnectedReadCycle
        when not defined(pvmReadCycleCreditWitness):
          echo "READ_CYCLE_ROLE_IMAGE,", extra, ",", image.codeBytes, ",", outsideImage.codeBytes
        when defined(pvmReadCycleCreditWitness):
          if extra == 0:
            # The literal receipt and verified RX together witness refill and paid-Read rollback.
            checkRoleEntry(cycle, image, extra, RoleExit.LaterMiss, quotaRefill = true)
        for exit in RoleExit:
          if exit == RoleExit.Outside:
            checkRoleEntry(outside, outsideImage, extra, exit)
          else:
            checkRoleEntry(cycle, image, extra, exit)

when NativeReadCycleEnabled and defined(pvmX86Jit):
  proc tailPointerFixture(): NativeReadCycle =
    ## Each setup resets the Store base and advances the word that the next Tail will read.
    result = cycleFixture(outside = true)
    result.read = readFixture(false, 1)
    let setup = [operation(51, 3, uint32(wordAddress)), operation(200, 0xb9, 9),
      operation(149, 0x00, 0x40000000)]
    assert addNativeReadContinuation(result.read,
      NativeReadContinuation(header: setupHeader, terminal: 44, price: 3), setup)
    result.tailLoad = operation(57, 5, uint32(wordAddress))

  proc checkTailPointerEntry(image: NativeImage, writable: var array[8, byte],
      firstExtent: bool, lowByte: byte) =
    ## Force two overlapping Stores through one image and vary its live byte borrow on each entry.
    var registers = default(RegisterFile)
    registers[0] = RegisterValue(0x80000000'u64+uint64(lowByte))
    registers[3] = RegisterValue(wordAddress)
    registers[4] = RegisterValue(wordAddress+4)
    registers[10] = RegisterValue(tailAddress+4)
    let readOnly = [0xfe'u8, 0xff, 0xff, 0xff, 0x80, 0x21, 0x32, 0x43, 0x54, 0x65, 0x76, 0x87]
    let decoy = [0xa1'u8, 0, 0, 0, 0, 0, 0, 0]
    var dirty = 1'u64 shl (wordAddress shr 12)
    let live = initNativeReadRegion(wordAddress, writable)
    var context = NativeCycleContext(
      read: [default(NativeReadRegion), live, initNativeReadRegion(tailAddress, readOnly)],
      writable: [NativeCycleWritable(first: 0x13000),
        NativeCycleWritable(first: wordAddress, length: uint64(writable.len),
          data: cast[pointer](addr writable[0]))],
      dirty: cast[pointer](addr dirty), dirtyWords: 1, gas: 1000, remaining: 1000)
    if firstExtent:
      # The first matching readable extent must win over an overlapping readable decoy.
      context.read[0] = live
      context.read[1] = initNativeReadRegion(wordAddress, decoy)
    let destination =
      when defined(pvmX86Jit) and defined(pvmX86ResidentProof):
        enterNativeReadCycleAbiProof(image, registers, context)
      else:
        enterNativeReadCycle(image, registers, context)
    assert destination == layout.outsideHeader
    assert context.visits == [1'u64, 2, 2, 2, 1, 1, 0]
    assert context.gas == 900 and context.remaining == 940
    assert context.lastCompleted == uint64(ord(NativeCycleRole.Outer)) and context.paidRead == 0
    assert validNativeCycleReceipt(layout, destination, 1000, 1000, context)
    assert registers[5] == RegisterValue(uint64(lowByte)+1), "Tail must read the latest Store"
    assert registers[0] == RegisterValue(0x100000000'u64+uint64(lowByte))
    assert registers[1] == RegisterValue(64) and registers[3] == RegisterValue(wordAddress+4)
    assert registers[6] == RegisterValue(0x19) and registers[8] == RegisterValue(3)
    assert writable == [lowByte, 0, 0, 0, 0x6e, 0x7f, 0x80, 0x91]
    assert dirty == 1'u64 shl (wordAddress shr 12)

  proc checkTailPointerReuse() =
    ## Keep both backing arrays live while one published image enters twice.
    const original = [0x19'u8, 0x2a, 0x3b, 0x4c, 0x6e, 0x7f, 0x80, 0x91]
    var first = original
    var second = original
    assert (addr first[0]) != (addr second[0])
    var image = lowerNativeReadCycle(tailPointerFixture())
    assert image.ready and image.kind == NativeKind.ConnectedReadCycle
    checkTailPointerEntry(image, first, false, 1)
    checkTailPointerEntry(image, second, true, 9)
    assert first[0] == 1 and second[0] == 9

when NativeReadCycleEnabled and defined(pvmX86Jit):
  proc checkStoreDirtyBoundary() =
    ## Exercise first/last page authority across the boundary between bitmap words.
    const pageEnd = 0x3ffff'u64
    let storeHeader = layout.sites[NativeCycleRole.Store].header
    for address in [pageEnd-4, pageEnd-3, pageEnd-2, pageEnd-1, pageEnd]:
      var cycle = cycleFixture()
      cycle.word.displacement = address-wordAddress
      let image = lowerNativeReadCycle(cycle)
      assert image.ready and image.kind == NativeKind.ConnectedReadCycle
      if address <= pageEnd-3:
        checkEntry(image, false, 1000, 1000, tailHeader, 969, 976, ReadExit.UnpaidTail,
          storeAddress = address)
      else:
        checkEntry(image, false, 1000, 1000, storeHeader, 997, 996, ReadExit.UnpaidStore,
          storeAddress = address, trailingDirty = true)
        checkEntry(image, false, 1000, 1000, storeHeader, 997, 996, ReadExit.UnpaidStore,
          storeAddress = address, bitmapWords = 2)
        checkEntry(image, false, 1000, 1000, storeHeader, 997, 996, ReadExit.UnpaidStore,
          pageDirty = false, storeAddress = address, trailingDirty = true, bitmapWords = 2)
        checkEntry(image, false, 1000, 1000, tailHeader, 969, 976, ReadExit.UnpaidTail,
          storeAddress = address, trailingDirty = true, bitmapWords = 2)

proc runReadCycleExecution*() =
  ## Run the same checked entry witness for the selected host ISA.
  when defined(pvmReadCycleRoleWitness):
    # The role fixture is meaningful only through the checked x86 SysV entry.
    when not (defined(pvmX86Jit) and defined(pvmX86ResidentProof) and NativeReadCycleEnabled):
      {.error: "require the native x86 role witness profile".}
  when defined(pvmReadCycleBudgetWitness):
    # The private cases must execute the selected native lowerer.
    if not (NativeReadCycleEnabled and nativePlatformSupported()):
      quit "require a native read-cycle budget witness"
  when defined(pvmX86ReadCycleResident) or defined(pvmX86ResidentProof):
    # The private ABI profile must enter real x86 code, even on the first prepaid miss.
    if not (defined(pvmX86Jit) and defined(pvmX86ResidentProof) and
        NativeReadCycleEnabled and nativePlatformSupported()):
      quit "require the Linux x86-64 ABI witness"
  when NativeReadCycleEnabled:
    var image = lowerNativeReadCycle(cycleFixture())
    assert image.ready and image.kind == NativeKind.ConnectedReadCycle, "publish the read cycle image"
    # Read is prepaid. Setup and Store consume 31 gas and 24 attempts before the Tail miss.
    checkEntry(image, false, 1000, 1000, tailHeader, 969, 976, ReadExit.UnpaidTail)
    # Tail, Jump, Outer, and Gate complete. The next paid Read misses after a staged load.
    checkEntry(image, true, 1000, 1000, readHeader, 881, 943, ReadExit.LaterMiss)
    # With Tail memory available, each one-short budget must independently leave Tail unpaid.
    checkEntry(image, true, 41, 1000, tailHeader, 10, 976, ReadExit.UnpaidTail)
    checkEntry(image, true, 1000, 27, tailHeader, 969, 3, ReadExit.UnpaidTail)
    # The first prepaid Read reaches a late qword guard even at zero remaining budget.
    checkEntry(image, false, 0, 0, readHeader, 0, 0, ReadExit.FirstMiss)
    # The later Read succeeds only if its aliased live-in is reloaded at that entry.
    var overlap = lowerNativeReadCycle(cycleFixture(overlap = true))
    assert overlap.ready and overlap.kind == NativeKind.ConnectedReadCycle
    checkEntry(overlap, true, 1000, 57, setupHeader, 881, 0, ReadExit.Overlap)
    when defined(pvmReadCycleBudgetWitness):
      let storeHeader = layout.sites[NativeCycleRole.Store].header
      # Both budgets fit, but a clean destination page must leave the Store unpaid.
      checkEntry(image, true, 1000, 1000, storeHeader, 997, 996, ReadExit.UnpaidStore,
        pageDirty = false)
      var outsideImage = lowerNativeReadCycle(cycleFixture(outside = true))
      assert outsideImage.ready and outsideImage.kind == NativeKind.ConnectedReadCycle
      checkEntry(outsideImage, true, 1000, 1000, layout.outsideHeader, 942, 968, ReadExit.Outside)

      # The four-visit Store price is exactly 2^63, crossing the signed compare boundary.
      const groupPrice = 1'u64 shl 63
      const wideRemaining = groupPrice+100
      var wide = layout
      wide.sites[NativeCycleRole.Store].price = groupPrice div NativeCycleGroupVisits
      let wideCycle = cycleFixture(receiptLayout = wide)
      var wideImage = lowerNativeReadCycle(wideCycle)
      assert wideImage.ready and wideImage.kind == NativeKind.ConnectedReadCycle
      let wideBytes =
        when defined(pvmReadCycleCreditWitness):
          let emitted = x86ReadCycleInstructions(wideCycle)
          assert emitted.len > 0 and not hasCreditReservation(emitted),
            "wide weighted Store must select exact accounting"
          emitted
        else:
          newSeq[byte](0)
      checkEntry(wideImage, true, groupPrice+2, wideRemaining, storeHeader, groupPrice-1,
        wideRemaining-4, ReadExit.UnpaidStore, receiptLayout = wide, expectedImage = wideBytes)
      checkEntry(wideImage, true, groupPrice+3, wideRemaining, tailHeader, 0, wideRemaining-24,
        ReadExit.UnpaidTail, receiptLayout = wide, expectedImage = wideBytes)
    when defined(pvmReadCycleRoleWitness):
      runReadCycleRoleWitness()
    when defined(pvmX86Jit):
      checkTailPointerReuse()
      checkStoreDirtyBoundary()
  echo "PASS shared native read cycle execution"

when NativeReadCycleEnabled and defined(pvmSharedAsyncWitness):
  proc finishMailboxRead(runtime: NativeRuntime, session: NativeSession,
      kind: NativeKind): NativeCompilerObservation =
    ## Collect the real image through its exact registration before checking its certificate.
    result = waitNativeCompilerGate(runtime)
    assert result.point == NativeCompilerPoint.BeforePublish and result.kind == kind and
      result.hasImage
    releaseNativeCompilerGate(runtime)
    waitNativeCompiler(runtime)
    beginNativeInvocation(session, NativeInvocationFloor)
    assert nativeState(session) == NativeState.Ready

  proc runReadCycleMailbox*() =
    ## Reuse the locked mailbox across both ABIs and retire a cancelled worker-owned image.
    assert nativePlatformSupported()
    let runtime = newNativeRuntime()
    try:
      assert start(runtime)
    except:
      assert false, "native compiler thread startup failed"
    let first = newNativeSession(runtime)
    let waiting = newNativeSession(runtime)
    let connected = cycleFixture()
    let alternate = cycleFixture(overlap = true)
    beginNativeInvocation(first, NativeInvocationFloor)
    nominateNativeReadCycle(first, connected)
    armNativeCompilerGate(runtime, NativeCompilerPoint.BeforePublish)
    finishNativeInvocation(first, NativeInvocationFloor)
    let firstKey = waitNativeCompilerGate(runtime)
    assert firstKey.kind == NativeKind.ConnectedReadCycle and firstKey.hasImage

    # An occupied mailbox preserves a complete, uncharged nomination in the other owner.
    beginNativeInvocation(waiting, NativeInvocationFloor)
    nominateNativeReadCycle(waiting, alternate)
    finishNativeInvocation(waiting, NativeInvocationFloor)
    assert nativeState(waiting) == NativeState.Deferred and runtimeInfo(runtime).registered == 1
    discard finishMailboxRead(runtime, first, NativeKind.ConnectedReadCycle)
    assert nativeReadCycleInfo(first) == connected.read.info
    assert matchesNativeReadCycle(first, connected) and not matchesNativeReadCycle(first, alternate)
    finishNativeInvocation(first, NativeInvocationFloor)
    invalidateNativeStream(first)
    assert runtimeInfo(runtime).registered == 0

    # Revalidating only the leaf keeps its checked continuation after the route changes.
    beginNativeInvocation(waiting, NativeInvocationFloor)
    assert nativeCycleNominated(waiting) and validateNativeRead(waiting, alternate.read)
    var changed = alternate
    inc changed.layout.outsideHeader
    validateNativeCycleNomination(waiting, changed)
    assert not nativeCycleNominated(waiting)
    armNativeCompilerGate(runtime, NativeCompilerPoint.BeforePublish)
    finishNativeInvocation(waiting, NativeInvocationFloor)
    let leafKey = finishMailboxRead(runtime, waiting, NativeKind.CheckedReadBody)
    assert leafKey.slot == firstKey.slot and leafKey.generation > firstKey.generation
    assert leafKey.ticket > firstKey.ticket and nativeReadInfo(waiting) == alternate.read.info
    assert nativeReadContinuation(waiting) == alternate.read.continuationInfo
    assert nativeReadCycleInfo(waiting).epoch == 0 and
      not matchesNativeReadCycle(waiting, alternate)
    finishNativeInvocation(waiting, NativeInvocationFloor)
    invalidateNativeStream(waiting)

    # Plain nomination after reuse cannot activate any route bytes retained by the old owner.
    let fresh = readFixture(overlap = true, epoch = nativeEpoch(waiting))
    beginNativeInvocation(waiting, NativeInvocationFloor)
    nominateNativeRead(waiting, fresh)
    assert not nativeCycleNominated(waiting) and nativeReadContinuation(waiting).terminal == 0
    armNativeCompilerGate(runtime, NativeCompilerPoint.BeforePublish)
    finishNativeInvocation(waiting, NativeInvocationFloor)
    let plainKey = finishMailboxRead(runtime, waiting, NativeKind.CheckedReadBody)
    assert plainKey.epoch == fresh.info.epoch and plainKey.ticket > leafKey.ticket
    assert nativeReadInfo(waiting) == fresh.info and nativeReadCycleInfo(waiting).epoch == 0
    assert nativeReadContinuation(waiting).terminal == 0
    finishNativeInvocation(waiting, NativeInvocationFloor)
    invalidateNativeStream(waiting)

    # A later full copy reaches the worker before cancellation retires its real mapping.
    let latest = cycleFixture(overlap = true, epoch = nativeEpoch(waiting))
    beginNativeInvocation(waiting, NativeInvocationFloor)
    nominateNativeReadCycle(waiting, latest)
    armNativeCompilerGate(runtime, NativeCompilerPoint.BeforePublish)
    finishNativeInvocation(waiting, NativeInvocationFloor)
    let latestKey = waitNativeCompilerGate(runtime)
    assert latestKey.kind == NativeKind.ConnectedReadCycle and latestKey.hasImage
    assert latestKey.ticket > plainKey.ticket and latestKey.epoch == latest.read.info.epoch
    invalidateNativeStream(waiting)
    releaseNativeCompilerGate(runtime, NativeCompilerPoint.BeforeRetire)
    let retiring = waitNativeCompilerGate(runtime)
    assert retiring.hasImage and retiring.ticket == latestKey.ticket and
      retiring.epoch == latestKey.epoch
    assert runtimeInfo(runtime).registered == 1 and runtimeInfo(runtime).completions == 0
    releaseNativeCompilerGate(runtime)
    waitNativeCompiler(runtime)
    let final = runtimeInfo(runtime)
    assert final.registered == 0 and final.submitted == 4 and final.completed == 3
    assert nativeState(waiting) == NativeState.Deferred and close(runtime)
    echo "PASS connected read mailbox reuse and retirement"

when NativeReadCycleEnabled and defined(pvmSharedAsyncWitness) and defined(pvmAuxLoop):
  proc readyAuxTestRenderer(runtime: NativeRuntime, session: NativeSession) =
    ## Publish a real ConnectedReadCycle using the normal primary path.
    beginNativeInvocation(session, NativeInvocationFloor)
    nominateNativeReadCycle(session, cycleFixture(epoch = nativeEpoch(session)))
    finishNativeInvocation(session, NativeInvocationFloor)
    waitNativeCompiler(runtime)
    beginNativeInvocation(session, NativeInvocationFloor)
    assert auxPrimaryReady(session)
    finishNativeInvocation(session, NativeInvocationFloor)

  proc auxTestBody(epoch: uint64): NativeReadBody =
    ## Two actual memory reads and nine scalar operations use the optional prefix ABI.
    result = initNativeAuxReadPrefix(64, 92, epoch)
    for i in 0..<11:
      let op = if i < 2: operation(58, byte(i), uint32(wordAddress))
        else: operation(149, 0x22, 1)
      assert addReadBodyOperation(result, 65+uint32(i), 92+uint32(i), op)
    assert result.complete

  proc runAuxiliaryMailbox*() =
    ## Force actual cancellation, pressure, idle/active retirement and close ordering.
    assert nativePlatformSupported()
    let runtime = newNativeRuntime()
    try:
      assert start(runtime)
    except:
      assert false, "native compiler thread startup failed"
    let renderer = newNativeSession(runtime)
    let other = newNativeSession(runtime)
    let priority = newNativeSession(runtime)
    readyAuxTestRenderer(runtime, renderer)
    readyAuxTestRenderer(runtime, other)
    let original = auxTestBody(nativeEpoch(renderer))

    # The optional job owns its image at the publication gate. A primary must still queue.
    beginNativeInvocation(renderer, NativeInvocationFloor)
    armNativeCompilerGate(runtime, NativeCompilerPoint.BeforePublish)
    assert not offerNativeAux(renderer, cycleFixture(epoch = nativeEpoch(renderer)).read)
    assert offerNativeAux(renderer, original)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    let optional = waitNativeCompilerGate(runtime)
    assert optional.kind == NativeKind.CheckedReadBody and optional.hasImage
    beginNativeInvocation(priority, NativeInvocationFloor)
    nominateNativeReadCycle(priority, cycleFixture())
    finishNativeInvocation(priority, NativeInvocationFloor)
    assert nativeState(priority) == NativeState.Pending
    assert runtimeInfo(runtime).registered == 4 and runtimeInfo(runtime).phase == NativePhase.Queued
    releaseNativeCompilerGate(runtime, NativeCompilerPoint.BeforeRetire)
    let retiring = waitNativeCompilerGate(runtime)
    assert retiring.ticket == optional.ticket and retiring.hasImage and
      runtimeInfo(runtime).registered == 4
    releaseNativeCompilerGate(runtime, NativeCompilerPoint.BeforePublish)
    let primary = waitNativeCompilerGate(runtime)
    assert primary.kind == NativeKind.ConnectedReadCycle and primary.hasImage and
      primary.ticket > optional.ticket and runtimeInfo(runtime).registered == 3
    releaseNativeCompilerGate(runtime)
    waitNativeCompiler(runtime)
    beginNativeInvocation(priority, NativeInvocationFloor)
    assert auxPrimaryReady(priority)
    finishNativeInvocation(priority, NativeInvocationFloor)
    beginNativeInvocation(renderer, NativeInvocationFloor)
    assert auxPrimaryReady(renderer) and not offerNativeAux(renderer, original)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    invalidateNativeStream(priority)

    # Cancel a pending optional payload by invalidating its exact primary epoch.
    beginNativeInvocation(renderer, NativeInvocationFloor)
    armNativeCompilerGate(runtime, NativeCompilerPoint.AfterClaim)
    assert offerNativeAux(renderer, original)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    let pending = waitNativeCompilerGate(runtime)
    assert pending.kind == NativeKind.CheckedReadBody and not pending.hasImage
    invalidateNativeStream(renderer)
    releaseNativeCompilerGate(runtime, NativeCompilerPoint.BeforeRetire)
    let cancelled = waitNativeCompilerGate(runtime)
    assert cancelled.ticket == pending.ticket and not cancelled.hasImage
    releaseNativeCompilerGate(runtime)
    waitNativeAuxiliary(runtime)
    assert runtimeInfo(runtime).registered == 1
    readyAuxTestRenderer(runtime, renderer)
    let next = auxTestBody(nativeEpoch(renderer))
    assert next.info.epoch != original.info.epoch
    beginNativeInvocation(renderer, NativeInvocationFloor)
    assert not offerNativeAux(renderer, original)
    assert offerNativeAux(renderer, next)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    waitNativeAuxiliary(runtime)
    beginNativeInvocation(other, NativeInvocationFloor)
    assert borrowNativeAux(other, next) == nil
    finishNativeInvocation(other, NativeInvocationFloor)

    # A borrowed runtime-owned mapping stays charged during pressure. Its next owner
    # boundary releases it while the already queued primary retains its own credit.
    beginNativeInvocation(renderer, NativeInvocationFloor)
    assert borrowNativeAux(renderer, original) == nil
    let image = borrowNativeAux(renderer, next)
    assert image != nil and image[].ready and image[].codeBytes > 0
    var bytes = newSeq[byte](8)
    bytes[0] = 137
    var registers = default(RegisterFile)
    var read = [initNativeReadRegion(wordAddress, bytes), default(NativeReadRegion),
      default(NativeReadRegion)]
    assert enterNativeReadBody(image[], registers, read)
    assert uint64(registers[0]) == 137 and uint64(registers[1]) == 137
    assert not close(runtime)
    let entrant = newNativeSession(runtime)
    beginNativeInvocation(entrant, NativeInvocationFloor)
    nominateNativeReadCycle(entrant, cycleFixture())
    finishNativeInvocation(entrant, NativeInvocationFloor)
    assert runtimeInfo(runtime).registered == 4 and nativeState(entrant) == NativeState.Pending
    waitNativeCompiler(runtime)
    beginNativeInvocation(entrant, NativeInvocationFloor)
    assert auxPrimaryReady(entrant)
    finishNativeInvocation(entrant, NativeInvocationFloor)

    # Let the first primary finish while the revoked borrowed image still holds the fourth credit.
    let delayed = newNativeSession(runtime)
    let delayedProof = cycleFixture()
    let beforeDelay = runtimeInfo(runtime)
    assert beforeDelay.phase == NativePhase.Done and beforeDelay.registered == 4
    beginNativeInvocation(delayed, NativeInvocationFloor)
    nominateNativeReadCycle(delayed, delayedProof)
    finishNativeInvocation(delayed, NativeInvocationFloor)
    assert nativeState(delayed) == NativeState.Deferred
    assert runtimeInfo(runtime).submitted == beforeDelay.submitted
    assert runtimeInfo(runtime).registered == 4

    # Retry after the original borrow returns and the owner finishes, without another owner entry.
    returnNativeAux(renderer)
    assert runtimeInfo(runtime).registered == 3 and auxPrimaryReady(renderer)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    beginNativeInvocation(delayed, NativeInvocationFloor)
    assert nativeCycleNominated(delayed) and validateNativeRead(delayed, delayedProof.read)
    validateNativeCycleNomination(delayed, delayedProof)
    finishNativeInvocation(delayed, NativeInvocationFloor)
    assert nativeState(delayed) == NativeState.Pending and nativeState(entrant) == NativeState.Ready
    assert runtimeInfo(runtime).submitted == beforeDelay.submitted+1 and
      runtimeInfo(runtime).registered == 4
    waitNativeCompiler(runtime)
    beginNativeInvocation(delayed, NativeInvocationFloor)
    assert auxPrimaryReady(delayed)
    finishNativeInvocation(delayed, NativeInvocationFloor)
    invalidateNativeStream(delayed)
    invalidateNativeStream(entrant)

    # An unrelated primary can reclaim a parked optional mapping while its owner is idle.
    beginNativeInvocation(renderer, NativeInvocationFloor)
    assert offerNativeAux(renderer, next)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    waitNativeAuxiliary(runtime)
    let idlePressure = newNativeSession(runtime)
    beginNativeInvocation(idlePressure, NativeInvocationFloor)
    nominateNativeReadCycle(idlePressure, cycleFixture())
    finishNativeInvocation(idlePressure, NativeInvocationFloor)
    assert runtimeInfo(runtime).registered == 3 and nativeState(idlePressure) == NativeState.Pending
    waitNativeCompiler(runtime)
    beginNativeInvocation(idlePressure, NativeInvocationFloor)
    assert auxPrimaryReady(idlePressure)
    finishNativeInvocation(idlePressure, NativeInvocationFloor)
    invalidateNativeStream(idlePressure)

    # An unrelated primary with a spare credit left over need not revoke a parked optional image.
    invalidateNativeStream(other)
    beginNativeInvocation(renderer, NativeInvocationFloor)
    assert offerNativeAux(renderer, next)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    waitNativeAuxiliary(runtime)
    readyAuxTestRenderer(runtime, other)
    beginNativeInvocation(renderer, NativeInvocationFloor)
    assert borrowNativeAux(renderer, next) != nil
    returnNativeAux(renderer)
    finishNativeInvocation(renderer, NativeInvocationFloor)

    # A parked optional mapping can retire at close without another call from its owner.
    assert runtimeInfo(runtime).registered == 3 and close(runtime)
    assert runtimeInfo(runtime).registered == 2
    beginNativeInvocation(renderer, NativeInvocationFloor)
    assert borrowNativeAux(renderer, next) == nil
    finishNativeInvocation(renderer, 0)
    invalidateNativeStream(renderer)
    invalidateNativeStream(other)
    assert runtimeInfo(runtime).registered == 0
    # Under host serialization close may overlap worker retirement, not another host handle call.
    try:
      assert start(runtime)
    except:
      assert false, "native compiler thread restart failed"
    readyAuxTestRenderer(runtime, renderer)
    let closing = auxTestBody(nativeEpoch(renderer))
    beginNativeInvocation(renderer, NativeInvocationFloor)
    armNativeCompilerGate(runtime, NativeCompilerPoint.BeforePublish)
    assert offerNativeAux(renderer, closing)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    let closingImage = waitNativeCompilerGate(runtime)
    assert closingImage.hasImage
    invalidateNativeStream(renderer)
    releaseNativeCompilerGate(runtime, NativeCompilerPoint.BeforeRetire)
    let closingRetirement = waitNativeCompilerGate(runtime)
    assert closingRetirement.ticket == closingImage.ticket and closingRetirement.hasImage
    assert runtimeInfo(runtime).active == 0 and runtimeInfo(runtime).registered == 1
    # Stop bypasses the worker gate. Close joins before it inspects or returns that credit.
    assert close(runtime)
    assert runtimeInfo(runtime).registered == 0 and runtimeInfo(runtime).completions == 0
