# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise both native lowerers against the same register, memory, and budget checkpoints.

import std/[assertions, syncio]
import ../../src/pvm/[machine, program]
import ../../src/pvm/internal/[native_ir, native_platform, native_read_body, native_read_cycle]
when NativeReadCycleEnabled and defined(pvmSharedAsyncWitness):
  import ../../src/pvm/internal/native_pipeline

when NativeReadCycleEnabled:
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
      receiptLayout = layout, pageDirty = true) =
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
    let initialDirty = if pageDirty: 1'u64 shl (wordAddress shr 12) else: 0'u64
    var dirty = initialDirty
    let readableRegion =
      if tailReadable: initNativeReadRegion(tailAddress, readable)
      else: initNativeReadRegion(tailAddress+4, readable.toOpenArray(4, 11))
    let wordReadable =
      if exit == ReadExit.FirstMiss: initNativeReadRegion(wordAddress, writable.toOpenArray(0, 6))
      else: initNativeReadRegion(wordAddress, writable)
    var context = NativeCycleContext(
      read: [default(NativeReadRegion), wordReadable, readableRegion],
      writable: [NativeCycleWritable(first: 0x13000),
        NativeCycleWritable(first: wordAddress, length: uint64(writable.len),
          data: cast[pointer](addr writable[0]))],
      dirty: cast[pointer](addr dirty), dirtyWords: 1, gas: gas, remaining: remaining,
      visits: [2'u64, 3, 4, 5, 6, 7, 8], lastCompleted: 9, paidRead: 9)
    let destination =
      when defined(pvmX86Jit) and defined(pvmX86ResidentProof):
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
    when defined(pvmReadCycleRoleWitness):
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
          of 0: operation(124, 0x36) # r6 = byte[r3], including the mapped base.
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
        exit: RoleExit) =
      ## Assert all lanes and memory after a real SysV call against a literal oracle.
      let (gas, remaining, header, finalGas, finalRemaining) = case exit
        of RoleExit.FirstMiss: (0'u64, 0'u64, readHeader, 0'u64, 0'u64)
        of RoleExit.StoreGas: (31'u64, 1000'u64, 50'u32, 0'u64, 976'u64)
        of RoleExit.StoreAttempts: (1000'u64, 43'u64, 50'u32, 969'u64, 19'u64)
        of RoleExit.TailPreflight: (1000'u64, 1000'u64, tailHeader, 941'u64, 956'u64)
        of RoleExit.Outside: (1000'u64, 1000'u64, 100'u32, 914'u64, 948'u64)
        of RoleExit.ReadGas: (146'u64, 1000'u64, readHeader, 59'u64, 947'u64)
        of RoleExit.LaterMiss: (1000'u64, 1000'u64, readHeader, 853'u64, 923'u64)
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
        dirty: cast[pointer](addr dirty), dirtyWords: 1, gas: gas, remaining: remaining,
        visits: [2'u64, 3, 4, 5, 6, 7, 8], lastCompleted: 9, paidRead: 9)
      let destination = enterNativeReadCycleAbiProof(image, registers, context)
      let paid = uint64(ord(exit in {RoleExit.FirstMiss, RoleExit.LaterMiss}))
      assert destination == header and
        context.gas == finalGas and context.remaining == finalRemaining
      assert context.visits == visits and context.lastCompleted == last and context.paidRead == paid
      assert validNativeCycleReceipt(cycle.layout, destination, gas, remaining, context)
      if last != NativeCycleNoCompleted:
        assert nativeCycleSuccessor(cycle, NativeCycleRole(last), registers) == destination
      assert registers == expected and writable == expectedMemory and dirty == initialDirty
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
        echo "READ_CYCLE_ROLE_IMAGE,", extra, ",", image.codeBytes, ",", outsideImage.codeBytes
        for exit in RoleExit:
          if exit == RoleExit.Outside:
            checkRoleEntry(outside, outsideImage, extra, exit)
          else:
            checkRoleEntry(cycle, image, extra, exit)

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
      var wideImage = lowerNativeReadCycle(cycleFixture(receiptLayout = wide))
      assert wideImage.ready and wideImage.kind == NativeKind.ConnectedReadCycle
      checkEntry(wideImage, true, groupPrice+2, wideRemaining, storeHeader, groupPrice-1,
        wideRemaining-4, ReadExit.UnpaidStore, receiptLayout = wide)
      checkEntry(wideImage, true, groupPrice+3, wideRemaining, tailHeader, 0, wideRemaining-24,
        ReadExit.UnpaidTail, receiptLayout = wide)
    when defined(pvmReadCycleRoleWitness):
      runReadCycleRoleWitness()
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
