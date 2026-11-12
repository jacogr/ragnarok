# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise both native lowerers against the same register, memory, and budget checkpoints.

import std/[assertions, syncio]
import ../../src/pvm/[machine, program]
import ../../src/pvm/internal/[native_ir, native_platform, native_read_body, native_read_cycle]
when defined(pvmReadCycleCreditWitness) and defined(pvmX86Jit) and NativeReadCycleEnabled:
  import ../../src/pvm/internal/x86_jit
when NativeReadCycleEnabled and defined(pvmSharedAsyncWitness):
  import ../../src/pvm/internal/[native_pipeline, native_auxiliary]

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

  proc readFixture(overlap: bool, epoch: uint64, first = 1'u32): NativeReadBody =
    ## Build the original paid Read without attaching the optional setup block.
    result = initNativeReadBody(readHeader, 33, first, first+23, epoch)
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
      assert addReadBodyOperation(result, readHeader+offset, first+offset, op),
        "append one source Read operation"

  proc cycleFixture(overlap = false, outside = false, receiptLayout = layout,
      epoch = 1'u64): NativeReadCycle =
    ## Extend the same paid Read with setup and the certified connected route.
    var read = readFixture(overlap, epoch, receiptLayout.sites[NativeCycleRole.Read].first)
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

  when defined(pvmX86Jit) or defined(pvmArm64Jit):
    import ../../src/pvm/internal/native_read_window

    type WindowCase {.pure.} = enum ## Literal extent and continuation choices for the same Read.
      Full, Short, Earlier, Wrapped, LaterMiss, PriorStore, ChangedBase

    func windowWord(bytes: array[40, byte], first, width: int): uint64 =
      ## Build the expected little-endian witness independently of the emitter.
      result = 0
      for i in 0..<width:
        result = result or (uint64(bytes[first+i]) shl (8*i))

    proc windowFixture(writeBase = false, outerWritesBase = false): NativeReadCycle =
      ## Reuse the same opcode shape with five ordered qwords based on r10.
      result = cycleFixture()
      let original = result.read
      var read = initNativeReadBody(readHeader, 33, 1, 24, 1)
      for index in 0..<22:
        # Deliberately choose a lane and displacements different from the DOOM certificate.
        let op = case index
          of 1:
            if writeBase: operation(151, 0xba)
            else: original.operation(index)
          of 2: operation(130, 0xa7, 32)
          of 4: operation(129, 0x36)
          of 8: operation(130, 0xa7, 48)
          of 12: operation(130, 0xa7, 64)
          of 17: operation(130, 0xa7, 40)
          of 19: operation(130, 0xa7, 56)
          of 20: operation(197, 0xbb, 9)
          of 21: operation(212, 0xbb, 9)
          else: original.operation(index)
        let offset = uint32(index)+1
        assert addReadBodyOperation(read, readHeader+offset, 1+offset, op)
      assert addNativeReadContinuation(read, original.continuationInfo,
        [original.operation(22), original.operation(23), original.operation(24)])
      result.read = read
      if outerWritesBase:
        # Change the qword base only after the first Read and Store commit.
        result.outer[1] = operation(149, 0xaa, 4096)

    proc checkWindowEntry(image: NativeImage, mode: WindowCase) =
      ## Compare complete register, writable memory and receipt checkpoints after actual native code.
      const first = 0x14000'u64
      var stack = default(array[40, byte])
      var other = default(array[40, byte])
      for i in 0..<stack.len:
        # Both descriptors hold distinguishable bytes for identical logical addresses.
        stack[i] = byte(0x11+i)
        other[i] = byte(0xa0+i)
      const initialWord = [0x19'u8, 0x2a, 0x3b, 0x4c, 0x6e, 0x7f, 0x80, 0x91]
      var word = initialWord
      let tail = [0xfe'u8, 0xff, 0xff, 0xff]
      let wordBase = if mode in {WindowCase.PriorStore,
          WindowCase.ChangedBase}: first+24 else: wordAddress
      let address = if mode == WindowCase.Wrapped: 0xffffffe0'u64 else: first
      let later = mode in {WindowCase.LaterMiss, WindowCase.PriorStore, WindowCase.ChangedBase}
      let gas = if later: 1000'u64 else: 0'u64
      let remaining = if later: 57'u64 else: 0'u64
      var dirty = 1'u64 shl (wordBase shr 12)

      var registers = default(RegisterFile)
      for i in 0..<registers.len:
        # Keep nonzero upper words in untouched lanes to detect accidental clobbers.
        registers[i] = RegisterValue(0x1234567800000000'u64+uint64(i))
      registers[0] = RegisterValue(0x1122334487665544'u64)
      registers[1] = RegisterValue(0)
      registers[3] = RegisterValue(wordBase)
      registers[4] = RegisterValue(wordBase+4)
      registers[8] = RegisterValue(0x7fffffff)
      registers[10] = RegisterValue(address-32)
      registers[11] = RegisterValue(0)
      registers[12] = RegisterValue(0xfffffffffffffffe'u64)

      let firstExtent = case mode
        of WindowCase.Short: initNativeReadRegion(address, stack.toOpenArray(0, 30))
        of WindowCase.Earlier: initNativeReadRegion(address+24, stack.toOpenArray(24, 31))
        else: initNativeReadRegion(address, stack)
      let otherExtent =
        if later: initNativeReadRegion(tailAddress, tail)
        else: initNativeReadRegion(address, other)
      let stackWritable =
        if mode in {WindowCase.PriorStore, WindowCase.ChangedBase}:
          NativeCycleWritable(first: first, length: uint64(stack.len),
            data: cast[pointer](addr stack[0]))
        else:
          NativeCycleWritable(first: 0x13000)
      var context = NativeCycleContext(
        read: [firstExtent, initNativeReadRegion(wordAddress, word.toOpenArray(0, 6)), otherExtent],
        writable: [stackWritable, NativeCycleWritable(first: wordAddress,
          length: uint64(word.len), data: cast[pointer](addr word[0]))],
        dirty: cast[pointer](addr dirty), dirtyWords: 1, gas: gas, remaining: remaining)

      var expected = registers
      var expectedWord = word
      var expectedStack = stack
      var visits = default(NativeCycleVisits)
      var last = NativeCycleNoCompleted
      var expectedHeader = readHeader
      if mode != WindowCase.Wrapped:
        # The final qword deliberately overlaps different descriptor winners in the short cases.
        expected[6] = RegisterValue(0x4c3b2a19'u64)
        expected[7] = RegisterValue(if mode == WindowCase.Short: windowWord(other, 24, 8)
                                   else: windowWord(stack, 24, 8))
        expected[9] = RegisterValue(0)
        visits[NativeCycleRole.Read] = 1
        last = uint64(ord(NativeCycleRole.Read))
        expectedHeader = setupHeader
      if later:
        # Tail and Outer complete before the next attempted Read.
        expected[1] = RegisterValue(32)
        expected[2] = RegisterValue(0x87)
        expected[3] = RegisterValue(wordBase+4)
        expected[5] = RegisterValue(high(uint64))
        expected[8] = RegisterValue(0xffffffff80000002'u64)
        expected[9] = RegisterValue(0x7c)
        visits = [1'u64, 1, 1, 1, 1, 1, 1]
        last = uint64(ord(NativeCycleRole.Gate))
        expectedHeader = readHeader
        if mode in {WindowCase.PriorStore, WindowCase.ChangedBase}:
          # The later proved window must load the same stack bytes the prior Store changed.
          expectedStack[24] = 0x44
          expectedStack[25] = 0x55
          expectedStack[26] = 0x66
          expectedStack[27] = 0x87
          if mode == WindowCase.ChangedBase:
            # The second Read must use the new base and discard its staged writes on a miss.
            expected[6] = RegisterValue(windowWord(stack, 24, 4))
            expected[8] = RegisterValue(0xffffffff80000000'u64)
            expected[10] = RegisterValue(first-32+4096)
          else:
            expected[6] = RegisterValue(windowWord(expectedStack, 28, 4))
            expected[7] = RegisterValue(windowWord(expectedStack, 24, 8))
            expected[9] = RegisterValue(0)
            visits[NativeCycleRole.Read] = 2
            last = uint64(ord(NativeCycleRole.Read))
            expectedHeader = setupHeader
        else:
          # The late S32 miss discards speculative U8 and qword writes after a committed Store.
          expectedWord[0] = 0x44
          expectedWord[1] = 0x55
          expectedWord[2] = 0x66
          expectedWord[3] = 0x87

      let destination =
        when defined(pvmX86Jit) and defined(pvmX86ResidentProof):
          enterNativeReadCycleAbiProof(image, registers, context)
        else:
          enterNativeReadCycle(image, registers, context)
      assert destination == expectedHeader and context.remaining == 0, "window resume and attempts"
      assert context.gas == (if later: 881'u64 else: 0'u64), "window gas"
      assert context.visits == visits and context.lastCompleted == last, "window completed roles"
      assert context.paidRead == uint64(ord(mode in {WindowCase.Wrapped, WindowCase.LaterMiss,
          WindowCase.ChangedBase})),
        "window paid Read status"
      assert validNativeCycleReceipt(layout, destination, gas, remaining, context), "window receipt"
      if registers != expected:
        # Report the differing lane and mode before failing the qualification.
        for lane in 0..<registers.len:
          if registers[lane] != expected[lane]:
            echo "WINDOW_CHECKPOINT,", ord(mode), ",", lane, ",", uint64(registers[lane]),
              ",", uint64(expected[lane])
        assert false, "window register checkpoint and descriptor priority"
      assert word == expectedWord and stack == expectedStack, "window committed Store bytes"
      assert dirty == 1'u64 shl (wordBase shr 12), "window dirty bitmap"

    proc checkReadWindow() =
      ## Check both lowerers against the same native entry and descriptor cases.
      let cycle = windowFixture()
      let proof = entryReadWindow(cycle)
      assert proof.operations == 0x000a1104'u32 and proof.first == 32 and proof.baseLane == 10
      assert entryReadWindow(windowFixture(writeBase = true)).operations == 0
      assert entryReadWindow(windowFixture(outerWritesBase = true)).operations == 0
      var image = lowerNativeReadCycle(cycle)
      assert image.ready and image.kind == NativeKind.ConnectedReadCycle
      for mode in WindowCase:
        # Every descriptor class gets a fresh invocation and independent expected state.
        if mode != WindowCase.ChangedBase:
          checkWindowEntry(image, mode)
      var changing = lowerNativeReadCycle(windowFixture(outerWritesBase = true))
      assert changing.ready and changing.kind == NativeKind.ConnectedReadCycle
      checkWindowEntry(changing, WindowCase.ChangedBase)

  type ReadExit {.pure.} = enum ## Which checkpoint the literal path reaches.
    UnpaidTail, LaterMiss, FirstMiss, Overlap, UnpaidStore, Outside

  proc checkEntry(image: NativeImage, tailReadable: bool, gas, remaining: uint64,
      expectedHeader: uint32, expectedGas, expectedRemaining: uint64, exit: ReadExit,
      receiptLayout = layout, pageDirty = true, expectedImage: openArray[byte] = [],
      storeAddress = wordAddress, trailingDirty = false, bitmapWords = 1'u64,
      auxiliarySlot = -1) =
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
    let destination = if auxiliarySlot >= 0:
        var raw = 0'u32
        assert tryEnterNativeAuxiliaryCycleAt(image, uint8(auxiliarySlot), registers, context, raw)
        raw
      else:
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

    when defined(pvmReadCycleCreditWitness):
      include ./pvm_read_cycle_shift_cases

when NativeReadCycleEnabled:
  proc tailPointerFixture(): NativeReadCycle =
    ## Each setup resets the Store base and advances the word that the next Tail will read.
    result = cycleFixture(outside = true)
    result.read = readFixture(false, 1)
    let setup = [operation(51, 3, uint32(wordAddress)), operation(200, 0xb9, 9),
      operation(149, 0x00, 0x40000000)]
    assert addNativeReadContinuation(result.read,
      NativeReadContinuation(header: setupHeader, terminal: 44, price: 3), setup)
    result.tailLoad = operation(57, 5, uint32(wordAddress))

  proc checkTailPointerEntry(image: NativeImage, writable: var array[4096, byte],
      firstExtent: bool, lowByte: byte) =
    ## Force two overlapping Stores on a proved page. Tail must observe the latest bytes.
    var expected = writable
    expected[0] = lowByte
    for i in 1..3:
      # The second Store clears the upper three bytes of the first word.
      expected[i] = 0
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
    assert writable == expected
    assert dirty == 1'u64 shl (wordAddress shr 12)

  proc checkTailPointerReuse() =
    ## Keep both backing arrays live while one published image enters twice.
    const original = [0x19'u8, 0x2a, 0x3b, 0x4c, 0x6e, 0x7f, 0x80, 0x91]
    var first = default(array[4096, byte])
    var second = default(array[4096, byte])
    for i in 0..<original.len:
      # Both pages expose the same guest address through different host allocations.
      first[i] = original[i]
      second[i] = original[i]
    assert (addr first[0]) != (addr second[0])
    var image = lowerNativeReadCycle(tailPointerFixture())
    assert image.ready and image.kind == NativeKind.ConnectedReadCycle
    checkTailPointerEntry(image, first, false, 1)
    checkTailPointerEntry(image, second, true, 9)
    assert first[0] == 1 and second[0] == 9

  proc checkStorePageBoundary() =
    ## The first word proves page 63. The next shares its tag and straddles into page 64.
    const
      first = 0x3f000'u64
      offset = 4089
      firstDirty = 1'u64 shl 63
      word = [0x44'u8, 0x55, 0x66, 0x87]
    var cycle = cycleFixture()
    cycle.word.displacement = first+uint64(offset)-wordAddress
    let image = lowerNativeReadCycle(cycle)
    assert image.ready and image.kind == NativeKind.ConnectedReadCycle
    let readable = [0x19'u8, 0x2a, 0x3b, 0x4c, 0x6e, 0x7f, 0x80, 0x91]
    let other = default(array[8, byte])
    for trailingDirty in [false, true]:
      # Exact quota 44 funds a second Store after x86 reconstructs the live credit ledger.
      let groups = if trailingDirty: 2'u64 else: 1'u64
      var writable = default(array[8192, byte])
      var expectedMemory = writable
      for i in 0..<int(groups)*word.len:
        # Compare the literal original Store bytes and all untouched neighbors.
        expectedMemory[offset+i] = word[i mod word.len]
      var registers = default(RegisterFile)
      registers[0] = RegisterValue(0x87665544)
      registers[3] = RegisterValue(wordAddress)
      registers[4] = RegisterValue(wordAddress+8)
      registers[10] = RegisterValue(tailAddress+4)
      var expected = registers
      expected[1] = RegisterValue(32*groups)
      expected[2] = RegisterValue(0x87)
      expected[3] = RegisterValue(wordAddress+4*groups)
      expected[6] = RegisterValue(0x19)
      expected[9] = RegisterValue(0x7c)
      let initialDirty = [firstDirty, uint64(ord(trailingDirty))]
      var dirty = initialDirty
      var context = NativeCycleContext(
        read: [default(NativeReadRegion), initNativeReadRegion(wordAddress, readable),
          initNativeReadRegion(tailAddress+4, other)],
        writable: [NativeCycleWritable(first: first+8192),
          NativeCycleWritable(first: first, length: 8192,
            data: cast[pointer](addr writable[0]))],
        dirty: cast[pointer](addr dirty[0]), dirtyWords: 2, gas: 1000, remaining: 44)
      let destination =
        when defined(pvmX86Jit) and defined(pvmX86ResidentProof):
          enterNativeReadCycleAbiProof(image, registers, context)
        else:
          enterNativeReadCycle(image, registers, context)
      let wanted = if trailingDirty: tailHeader else: layout.sites[NativeCycleRole.Store].header
      assert destination == wanted
      assert context.gas == 997-28*groups and context.remaining == 40-20*groups
      assert context.visits == [1'u64, 1, groups, 0, 0, 0, 0]
      assert context.lastCompleted == uint64(ord(NativeCycleRole.Store)) and context.paidRead == 0
      assert validNativeCycleReceipt(layout, destination, 1000, 44, context)
      assert registers == expected and writable == expectedMemory and dirty == initialDirty

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
    when defined(pvmReadCycleCreditWitness):
      checkResidentReadShifts()
    checkTailPointerReuse()
    checkStorePageBoundary()
    when defined(pvmX86Jit):
      checkStoreDirtyBoundary()
      assert nativePlatformSupported()
    checkReadWindow()
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

when NativeReadCycleEnabled and defined(pvmSharedAsyncWitness):
  import ../../src/pvm/internal/native_mixed_loop

  import ./pvm_register_ring

  proc readyMixedLoopTestRenderer(runtime: NativeRuntime, session: NativeSession, ring = false) =
    ## Publish an ordinary primary under its existing queue and collection rules.
    beginNativeInvocation(session, NativeInvocationFloor)
    if ring:
      nominateNativeRing(session, registerRingFixture([3'u64, 2, 5]), nativeEpoch(session))
    else:
      nominateNativeReadCycle(session, cycleFixture(epoch = nativeEpoch(session)))
    finishNativeInvocation(session, NativeInvocationFloor)
    waitNativeCompiler(runtime)
    beginNativeInvocation(session, NativeInvocationFloor)
    assert mixedLoopPrimaryReady(session)
    finishNativeInvocation(session, NativeInvocationFloor)

  proc mixedLoopTestProof(epoch: uint64): NativeMixedLoop =
    ## Use an independently decoded test shape disjoint from the primary's stream geometry.
    result = NativeMixedLoop(header: 128, first: 192, terminal: 143, exitHeader: 144,
      price: 102, epoch: epoch, span: 15, count: 15)
    let operations = [operation(152, 0x57, 4),
        operation(210, 0x97, 7), operation(58, 10, uint32(wordAddress)),
        operation(139, 0x58, 26), operation(212, 0x87, 7),
        operation(58, 8, uint32(wordAddress+8)), operation(200, 0xa7, 7),
        operation(124, 0x77), operation(200, 0x87, 7), operation(124, 0x77),
        operation(149, 0xb8, 1), operation(120, 0xb7), operation(190, 0x25, 5),
        operation(100, 0xb8), operation(171, 0x38)]
    for index, item in operations: result.operations[index] = item

  proc mixedLoopTestPair(proof: NativeMixedLoop): NativeMixedLoopSet =
    ## Copy two genuinely disjoint source/handler intervals under the same primary epoch.
    result = singleNativeMixedLoop(proof)
    result.count = 2
    result.proofs[1] = proof
    result.proofs[1].header += 512
    result.proofs[1].terminal += 512
    result.proofs[1].exitHeader += 512
    result.proofs[1].first += 512
    assert result.complete

  proc runMixedLoopMailboxCase[Paired, Ring: static[bool]]() =
    ## Force the same real scheduler lifecycle for either one entry or a disjoint two-entry arena.
    template candidates(proof: NativeMixedLoop): NativeMixedLoopSet =
      when Paired: mixedLoopTestPair(proof)
      else: singleNativeMixedLoop(proof)
    template offer(session: NativeSession, proof: NativeMixedLoop): bool =
      offerNativeMixedLoops(session, candidates(proof))
    var lease = default(NativeAuxiliaryLease)
    template borrow(session: NativeSession, proof: NativeMixedLoop): NativeMixedLoopBorrow =
      borrowNativeMixedLoops(session, candidates(proof), lease)
    assert nativePlatformSupported()
    let runtime = newNativeRuntime()
    try:
      assert start(runtime)
    except:
      assert false, "native compiler thread startup failed"
    let renderer = newNativeSession(runtime)
    let other = newNativeSession(runtime)
    let priority = newNativeSession(runtime)
    readyMixedLoopTestRenderer(runtime, renderer, ring = Ring)

    # Keep both jobs queued without pressure so a later primary can claim first.
    let queuedPriority = newNativeSession(runtime)
    let queuedProof = mixedLoopTestProof(nativeEpoch(renderer))
    when Ring:
      # Protect every installed ring block in both coordinate spaces before queueing.
      let ring = registerRingFixture([3'u64, 2, 5])
      for item in ring.blocks:
        var physical = queuedProof
        physical.header = item.header
        physical.terminal = item.header+uint32(physical.count)
        physical.exitHeader = physical.terminal+1
        assert physical.complete and not mixedLoopDisjoint(renderer, physical)
        var source = queuedProof
        source.first = item.first
        assert source.complete and not mixedLoopDisjoint(renderer, source)
      assert mixedLoopDisjoint(renderer, queuedProof)
    let beforeAuxiliary = runtimeInfo(runtime)
    pauseNativeCompiler(runtime, true)
    beginNativeInvocation(renderer, NativeInvocationFloor)
    var malformed = candidates(queuedProof)
    malformed.count = uint8(NativeMixedLoopEntryLimit+1)
    assert not malformed.complete and not sameNativeMixedLoopSet(malformed, malformed)
    assert not offerNativeMixedLoops(renderer, malformed)
    let malformedBorrow = borrowNativeMixedLoops(renderer, malformed, lease)
    assert not lease.ready and not malformedBorrow.settled
    malformed.count = 0
    assert not offerNativeMixedLoops(renderer, malformed)
    discard borrowNativeMixedLoops(renderer, malformed, lease)
    assert not lease.ready
    # An invalid caller coordinate cannot reach the certified typed refusal-token assertion.
    malformed = candidates(queuedProof)
    malformed.proofs[0].header = NativeEntryLimit
    discard borrowNativeMixedLoops(renderer, malformed, lease)
    assert not lease.ready
    when Paired:
      var highSource = candidates(queuedProof)
      highSource.proofs[0].first = high(uint32)-uint32(queuedProof.span)+1
      highSource.proofs[1].first = highSource.proofs[0].first
      assert highSource.proofs[0].complete and highSource.proofs[1].complete
      assert not highSource.complete and not offerNativeMixedLoops(renderer, highSource)
    assert offer(renderer, queuedProof)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    let queuedAuxiliary = runtimeInfo(runtime)
    assert queuedAuxiliary.phase == NativePhase.Queued and
      queuedAuxiliary.submitted == beforeAuxiliary.submitted+1 and
      queuedAuxiliary.completed == beforeAuxiliary.completed
    beginNativeInvocation(queuedPriority, NativeInvocationFloor)
    nominateNativeReadCycle(queuedPriority, cycleFixture())
    finishNativeInvocation(queuedPriority, NativeInvocationFloor)
    assert nativeState(queuedPriority) == NativeState.Pending and runtimeInfo(runtime).registered == 3,
      "both optional and primary jobs must be queued"
    armNativeCompilerGate(runtime, NativeCompilerPoint.AfterClaim)
    pauseNativeCompiler(runtime, false)
    let firstClaim = waitNativeCompilerGate(runtime)
    assert firstClaim.kind == NativeKind.ConnectedReadCycle and not firstClaim.hasImage,
      "queued primary must claim before queued optional work"
    releaseNativeCompilerGate(runtime)
    waitNativeCompiler(runtime)
    let completedAuxiliary = runtimeInfo(runtime)
    assert completedAuxiliary.phase == NativePhase.Done and
      completedAuxiliary.submitted == beforeAuxiliary.submitted+2 and
      completedAuxiliary.completed == beforeAuxiliary.completed+2
    beginNativeInvocation(queuedPriority, NativeInvocationFloor)
    assert mixedLoopPrimaryReady(queuedPriority)
    finishNativeInvocation(queuedPriority, NativeInvocationFloor)
    beginNativeInvocation(renderer, NativeInvocationFloor)
    let parked = nativeOwnerStatistics(renderer)
    assert parked[0] == 2 and parked[3] > nativeStatistics(renderer)[3]
    assert nativeOwnerStatistics(renderer) == parked
    let queuedBorrow = borrow(renderer, queuedProof)
    assert queuedBorrow.mask == (when Paired: 3'u8 else: 1'u8) and not queuedBorrow.pairRefused
    assert lease.ready, "optional work must resume after primary"
    assert nativeOwnerStatistics(renderer) == parked
    returnNativeAuxiliary(lease)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    invalidateNativeStream(queuedPriority)
    invalidateNativeStream(renderer)
    readyMixedLoopTestRenderer(runtime, renderer, ring = Ring)
    readyMixedLoopTestRenderer(runtime, other)
    let original = mixedLoopTestProof(nativeEpoch(renderer))

    # The optional job owns its image at the publication gate. A primary must still queue.
    beginNativeInvocation(renderer, NativeInvocationFloor)
    armNativeCompilerGate(runtime, NativeCompilerPoint.BeforePublish)
    assert offer(renderer, original)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    let optional = waitNativeCompilerGate(runtime)
    assert optional.kind == NativeKind.AuxiliaryArena and optional.hasImage
    assert runtimeInfo(runtime).phase == NativePhase.Running
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
    assert mixedLoopPrimaryReady(priority)
    finishNativeInvocation(priority, NativeInvocationFloor)
    beginNativeInvocation(renderer, NativeInvocationFloor)
    assert mixedLoopPrimaryReady(renderer) and not offer(renderer, original)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    invalidateNativeStream(priority)

    # Cancel a pending optional payload by invalidating its exact primary epoch.
    beginNativeInvocation(renderer, NativeInvocationFloor)
    armNativeCompilerGate(runtime, NativeCompilerPoint.AfterClaim)
    assert offer(renderer, original)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    let pending = waitNativeCompilerGate(runtime)
    assert pending.kind == NativeKind.AuxiliaryArena and not pending.hasImage
    invalidateNativeStream(renderer)
    releaseNativeCompilerGate(runtime, NativeCompilerPoint.BeforeRetire)
    let cancelled = waitNativeCompilerGate(runtime)
    assert cancelled.ticket == pending.ticket and not cancelled.hasImage
    releaseNativeCompilerGate(runtime)
    waitNativeCompiler(runtime)
    assert runtimeInfo(runtime).registered == 1
    readyMixedLoopTestRenderer(runtime, renderer, ring = Ring)
    let next = mixedLoopTestProof(nativeEpoch(renderer))
    assert next.epoch != original.epoch
    beginNativeInvocation(renderer, NativeInvocationFloor)
    assert not offer(renderer, original)
    assert offer(renderer, next)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    waitNativeCompiler(runtime)
    beginNativeInvocation(other, NativeInvocationFloor)
    discard borrow(other, next)
    assert not lease.ready
    finishNativeInvocation(other, NativeInvocationFloor)

    # A borrowed runtime-owned mapping stays charged during pressure. Its next owner
    # boundary releases it while the already queued primary retains its own credit.
    beginNativeInvocation(renderer, NativeInvocationFloor)
    discard borrow(renderer, original)
    assert not lease.ready
    discard borrow(renderer, next)
    assert lease.ready and auxiliaryCodeBytes(lease) > 0
    assert not close(runtime)
    let entrant = newNativeSession(runtime)
    beginNativeInvocation(entrant, NativeInvocationFloor)
    nominateNativeReadCycle(entrant, cycleFixture())
    finishNativeInvocation(entrant, NativeInvocationFloor)
    assert runtimeInfo(runtime).registered == 4 and nativeState(entrant) == NativeState.Pending
    waitNativeCompiler(runtime)
    beginNativeInvocation(entrant, NativeInvocationFloor)
    assert mixedLoopPrimaryReady(entrant)
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
    var registers = default(RegisterFile)
    var emptyContext = NativeMixedLoopContext(visitLimit: 1)
    assert enterBorrowedAuxiliaryLoop(lease, 0, registers, emptyContext) == 0
    when Paired:
      assert auxiliaryEntries(lease) == 3
      assert enterBorrowedAuxiliaryLoop(lease, 1, registers, emptyContext) == 0
    assert registers == default(RegisterFile)
    returnNativeAuxiliary(lease)
    assert runtimeInfo(runtime).registered == 3 and mixedLoopPrimaryReady(renderer)
    let afterPressure = nativeOwnerStatistics(renderer)
    assert afterPressure[0] > nativeStatistics(renderer)[0] and afterPressure[3] ==
        nativeStatistics(renderer)[3]
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
    assert mixedLoopPrimaryReady(delayed)
    finishNativeInvocation(delayed, NativeInvocationFloor)
    invalidateNativeStream(delayed)
    invalidateNativeStream(entrant)

    # An unrelated primary can reclaim a parked optional mapping while its owner is idle.
    beginNativeInvocation(renderer, NativeInvocationFloor)
    assert offer(renderer, next)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    waitNativeCompiler(runtime)
    let idlePressure = newNativeSession(runtime)
    beginNativeInvocation(idlePressure, NativeInvocationFloor)
    nominateNativeReadCycle(idlePressure, cycleFixture())
    finishNativeInvocation(idlePressure, NativeInvocationFloor)
    assert runtimeInfo(runtime).registered == 3 and nativeState(idlePressure) == NativeState.Pending
    waitNativeCompiler(runtime)
    beginNativeInvocation(idlePressure, NativeInvocationFloor)
    assert mixedLoopPrimaryReady(idlePressure)
    finishNativeInvocation(idlePressure, NativeInvocationFloor)
    invalidateNativeStream(idlePressure)

    # An unrelated primary with a spare credit left over need not revoke a parked optional image.
    invalidateNativeStream(other)
    beginNativeInvocation(renderer, NativeInvocationFloor)
    assert offer(renderer, next)
    finishNativeInvocation(renderer, NativeInvocationFloor)
    waitNativeCompiler(runtime)
    readyMixedLoopTestRenderer(runtime, other)
    beginNativeInvocation(renderer, NativeInvocationFloor)
    discard borrow(renderer, next)
    assert lease.ready
    returnNativeAuxiliary(lease)
    finishNativeInvocation(renderer, NativeInvocationFloor)

    # A parked optional mapping can retire at close without another call from its owner.
    assert runtimeInfo(runtime).registered == 3 and close(runtime)
    assert runtimeInfo(runtime).registered == 2
    beginNativeInvocation(renderer, NativeInvocationFloor)
    discard borrow(renderer, next)
    assert not lease.ready
    finishNativeInvocation(renderer, 0)
    invalidateNativeStream(renderer)
    invalidateNativeStream(other)
    assert runtimeInfo(runtime).registered == 0
    # Under host serialization close may overlap worker retirement, not another host handle call.
    try:
      assert start(runtime)
    except:
      assert false, "native compiler thread restart failed"
    readyMixedLoopTestRenderer(runtime, renderer, ring = Ring)
    let closing = mixedLoopTestProof(nativeEpoch(renderer))
    when defined(pvmX86Jit):
      var oversized = NativeMixedLoop(header: 160, first: 256, terminal: 192, exitHeader: 193,
        price: 102, epoch: nativeEpoch(renderer), span: 32, count: 32)
      for index in 0..<30: oversized.operations[index] = operation(124, 0x77)
      oversized.operations[30] = operation(120, 0xb7)
      oversized.operations[31] = operation(171, 0x38)
      assert oversized.complete
      beginNativeInvocation(renderer, NativeInvocationFloor)
      assert offer(renderer, oversized)
      finishNativeInvocation(renderer, NativeInvocationFloor)
      waitNativeCompiler(runtime)
      let rejected = runtimeInfo(runtime)
      assert rejected.registered == 1 and rejected.completions == 0
      beginNativeInvocation(renderer, NativeInvocationFloor)
      let refused = borrow(renderer, oversized)
      assert not lease.ready and refused.refused
      assert not offer(renderer, oversized)
      assert runtimeInfo(runtime).submitted == rejected.submitted
      finishNativeInvocation(renderer, NativeInvocationFloor)
    beginNativeInvocation(renderer, NativeInvocationFloor)
    armNativeCompilerGate(runtime, NativeCompilerPoint.BeforePublish)
    assert offer(renderer, closing)
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

  proc runMixedLoopMailbox*() =
    runMixedLoopMailboxCase[false, false]()
    runMixedLoopMailboxCase[true, false]()
    runMixedLoopMailboxCase[false, true]()
    runMixedLoopMailboxCase[true, true]()

  proc runMixedArenaPublishRefusal*() =
    ## A real partial arena publication failure must never become a callable worker completion.
    let runtime = newNativeRuntime()
    try:
      assert start(runtime)
    except:
      assert false, "mixed arena refusal worker failed to start"
    let renderer = newNativeSession(runtime)
    readyMixedLoopTestRenderer(runtime, renderer)
    let requested = mixedLoopTestPair(mixedLoopTestProof(nativeEpoch(renderer)))
    let baseline = runtimeInfo(runtime)
    let owner = nativeOwnerStatistics(renderer)
    assert owner[0] == 1 and owner[3] > 0
    for attempt in 0..1:
      beginNativeInvocation(renderer, NativeInvocationFloor)
      armNativeCompilerGate(runtime, NativeCompilerPoint.BeforePublish)
      assert offerNativeMixedLoops(renderer, requested)
      finishNativeInvocation(renderer, NativeInvocationFloor)
      let failed = waitNativeCompilerGate(runtime)
      assert failed.kind == NativeKind.AuxiliaryArena and not failed.hasImage
      let pending = runtimeInfo(runtime)
      assert pending.registered == 2 and pending.phase == NativePhase.Running
      assert nativeOwnerStatistics(renderer) == owner
      releaseNativeCompilerGate(runtime)
      waitNativeCompiler(runtime)
      let retired = runtimeInfo(runtime)
      assert retired.registered == 1 and retired.completions == 0
      assert retired.submitted == baseline.submitted+uint64(attempt)+1
      assert retired.completed == baseline.completed
      beginNativeInvocation(renderer, NativeInvocationFloor)
      var lease = default(NativeAuxiliaryLease)
      let borrow = borrowNativeMixedLoops(renderer, requested, lease)
      assert borrow.settled and not borrow.pending and not lease.ready
      assert borrow.mask == 0 and borrow.refusedMask == 0 and not borrow.pairRefused
      assert nativeOwnerStatistics(renderer) == owner and mixedLoopPrimaryReady(renderer)
      finishNativeInvocation(renderer, NativeInvocationFloor)
      echo "MIXED_ARENA_ASYNC_REFUSAL,", attempt, ",", retired.submitted-baseline.submitted,
        ",", retired.completed-baseline.completed, ",", retired.registered
    invalidateNativeStream(renderer)
    assert runtimeInfo(runtime).registered == 0 and close(runtime)

  proc typedCycleFixture(first: uint32, epoch: uint64): NativeReadCycle =
    ## Keep role source intervals distinct and contiguous independently of cached headers.
    var typedLayout = layout
    var next = first
    for role in NativeCycleRole:
      typedLayout.sites[role].first = next
      next += uint32(NativeCycleSpans[role])
    cycleFixture(receiptLayout = typedLayout, epoch = epoch)

  proc typedReadOnlyProof(epoch: uint64): NativeMixedLoop =
    ## Bind a bounded Read, pointer increment, and original signed backedge.
    result = NativeMixedLoop(header: 128, first: 192, terminal: 131, exitHeader: 132,
      price: 3, epoch: epoch, span: 3, count: 3)
    result.operations[0] = operation(124, 0x36) # r6 = byte[r3]
    result.operations[1] = operation(149, 0x33, 1)
    result.operations[2] = operation(173, 0x43) # repeat while r3 <s r4

  proc runTypedAuxiliaryNative*() =
    ## Execute both ABIs from one RX image and repeat the existing literal Read receipts there.
    let cycle = typedCycleFixture(1, 1)
    let typedLayout = cycle.layout
    let loop = typedReadOnlyProof(cycle.read.info.epoch)
    var plan = initNativeAuxiliaryPlan(cycle.read.info.epoch)
    assert plan.add(cycle) and plan.add(loop)
    var request = default(NativeAuxiliaryRequest)
    assert newNativeAuxiliaryRequest(plan, request) == NativeAuxiliaryBuildStatus.Ready
    var owned = move(request)
    assert request.isEmpty and not owned.isEmpty
    var copied = default(NativeAuxiliaryPlan)
    assert copyNativeAuxiliaryPlan(owned, copied) and sameNativeAuxiliaryPlan(owned, copied)
    var refused = 0'u8
    var pairRefused = false
    let image = lowerNativeAuxiliary(plan, refused, pairRefused)
    assert image.ready and image.kind == NativeKind.AuxiliaryArena
    assert nativeMixedLoopEntries(image) == 3 and refused == 0 and not pairRefused
    assert image.codeBytes > 0 and image.codeBytes <= uint64(NativeImageByteLimit)

    let data = [0x31'u8, 0x42]
    let region = initNativeReadRegion(wordAddress, data)
    var registers = default(RegisterFile)
    registers[3] = RegisterValue(wordAddress)
    registers[4] = RegisterValue(wordAddress+2)
    let original = registers
    var loopContext = NativeMixedLoopContext(read: [region, default(NativeReadRegion),
      default(NativeReadRegion)], visitLimit: 2)
    var cycleContext = NativeCycleContext(read: loopContext.read, gas: 123, remaining: 456,
      lastCompleted: NativeCycleNoCompleted)
    var raw = high(uint32)
    assert not tryEnterNativeAuxiliaryLoopAt(image, 0, registers, loopContext, raw)
    assert raw == 0 and registers == original and loopContext.visitLimit == 2
    raw = high(uint32)
    assert not tryEnterNativeAuxiliaryCycleAt(image, 1, registers, cycleContext, raw)
    assert raw == 0 and registers == original and cycleContext.gas == 123 and
      cycleContext.remaining == 456 and cycleContext.lastCompleted == NativeCycleNoCompleted
    assert data == [0x31'u8, 0x42]

    assert tryEnterNativeAuxiliaryLoopAt(image, 1, registers, loopContext, raw)
    let receipt = nativeMixedLoopReceipt(loop, 2, raw, registers)
    assert receipt.valid and receipt.visits == 2 and not receipt.paid and receipt.next ==
        loop.exitHeader
    assert uint64(registers[3]) == wordAddress+2 and uint64(registers[6]) == 0x42

    checkEntry(image, false, 1000, 1000, tailHeader, 969, 976, ReadExit.UnpaidTail,
      receiptLayout = typedLayout, auxiliarySlot = 0)
    checkEntry(image, true, 1000, 1000, readHeader, 881, 943, ReadExit.LaterMiss,
      receiptLayout = typedLayout, auxiliarySlot = 0)
    checkEntry(image, false, 0, 0, readHeader, 0, 0, ReadExit.FirstMiss,
      receiptLayout = typedLayout, auxiliarySlot = 0)
    checkEntry(image, true, 1000, 1000, typedLayout.sites[NativeCycleRole.Store].header,
      997, 996, ReadExit.UnpaidStore, receiptLayout = typedLayout, pageDirty = false,
          auxiliarySlot = 0)
    echo "PASS typed auxiliary image and both ABI guards"

  proc runTypedAuxiliaryMailbox*() =
    ## Borrow the exact heterogeneous request, then revoke it under real primary pressure.
    let runtime = newNativeRuntime()
    try:
      assert start(runtime)
    except:
      assert false, "typed auxiliary worker startup failed"
    let owner = newNativeSession(runtime)
    let other = newNativeSession(runtime)
    readyMixedLoopTestRenderer(runtime, owner, ring = true)
    readyMixedLoopTestRenderer(runtime, other, ring = true)
    let epoch = nativeEpoch(owner)
    assert epoch == nativeEpoch(other)
    let cycle = typedCycleFixture(64, epoch)
    let loop = typedReadOnlyProof(epoch)
    var exact = initNativeAuxiliaryPlan(epoch)
    assert exact.add(cycle) and exact.add(loop)

    beginNativeInvocation(owner, NativeInvocationFloor)
    let primary = nativeInstalledKey(owner)
    assert offerNativeAuxiliary(owner, primary, exact)
    finishNativeInvocation(owner, NativeInvocationFloor)
    waitNativeCompiler(runtime)
    assert runtimeInfo(runtime).registered == 3 and runtimeInfo(runtime).completions == 1

    var lease = default(NativeAuxiliaryLease)
    beginNativeInvocation(other, NativeInvocationFloor)
    let wrongOwner = borrowNativeAuxiliary(other, nativeInstalledKey(other), exact, lease)
    assert wrongOwner.settled and not wrongOwner.matched and not lease.ready
    finishNativeInvocation(other, NativeInvocationFloor)
    beginNativeInvocation(owner, NativeInvocationFloor)
    var changed = cycle
    changed.word.displacement += 1
    var wrong = initNativeAuxiliaryPlan(epoch)
    assert wrong.add(changed) and wrong.add(loop)
    let wrongProof = borrowNativeAuxiliary(owner, primary, wrong, lease)
    assert wrongProof.settled and not wrongProof.matched and not lease.ready
    var reversed = initNativeAuxiliaryPlan(epoch)
    assert reversed.add(loop) and reversed.add(cycle)
    let wrongOrder = borrowNativeAuxiliary(owner, primary, reversed, lease)
    assert wrongOrder.settled and not wrongOrder.matched and not lease.ready
    let borrowed = borrowNativeAuxiliary(owner, primary, exact, lease)
    assert borrowed.settled and borrowed.matched and borrowed.mask == 3 and lease.ready
    var moved = move(lease)
    assert not lease.ready and moved.ready and auxiliaryCodeBytes(moved) > 0
    assert auxiliaryEntryMatches(moved, 0, NativeAuxiliaryKind.ReadCycle) and
      auxiliaryEntryMatches(moved, 1, NativeAuxiliaryKind.SelfLoop)

    let entrant = newNativeSession(runtime)
    beginNativeInvocation(entrant, NativeInvocationFloor)
    nominateNativeReadCycle(entrant, cycleFixture())
    finishNativeInvocation(entrant, NativeInvocationFloor)
    # Primary pressure revokes the borrowed image but cannot recycle its row.
    assert runtimeInfo(runtime).registered == 4 and nativeState(entrant) == NativeState.Pending
    waitNativeCompiler(runtime)
    var registers = default(RegisterFile)
    var empty = NativeCycleContext(lastCompleted: NativeCycleNoCompleted)
    var lastHeader = cycle.read.info.header
    assert runBorrowedAuxiliaryCycle(owner, moved, 0, cycle, registers, empty, lastHeader) ==
      cycle.read.info.header
    assert empty.paidRead == 1 and empty.lastCompleted == NativeCycleNoCompleted
    assert registers == default(RegisterFile)
    assert not close(runtime)
    returnNativeAuxiliary(moved)
    assert not moved.ready and runtimeInfo(runtime).registered == 3
    let retired = borrowNativeAuxiliary(owner, primary, exact, lease)
    assert retired.settled and not retired.matched and not lease.ready

    finishNativeInvocation(owner, NativeInvocationFloor)
    invalidateNativeStream(entrant)
    invalidateNativeStream(other)
    invalidateNativeStream(owner)
    assert runtimeInfo(runtime).registered == 0 and close(runtime)
