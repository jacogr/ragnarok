# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Direct original-source and checked-frame comparisons for a read-only signed loop.

when declared(FlatFrame) and defined(pvmMixedLoopEntryWitness) and defined(pvmPaidMixedLoopWitness):
  type ReadOnlyLoopCase {.pure.} = enum
    NegativeThreshold, NegativeLoad, HighBitLoad, ChangedAddress, MinimumBound, MaximumBound,
      ExactQuota,
    PartialQuota, ExactGas, InsufficientGas, FirstWidthFault, LaterWidthFault, ZeroQuota

  proc flatReadOnlyWitnessExit(f: var FlatFrame, off: uint32): uint32 =
    ## Stop both private controls at the same original outside header before its unrelated work.
    f.info.pc = CodeAddress(uint64(f.plan.facts[int(f.sites[int(off)])].pc))
    f.info.blockCharged = false
    f.reason = oracle.StepError.None
    f.exit = oracle.StepExit.Continued
    f.stoppedAt = off
    f.attemptedExit = false
    flatStop

  proc readOnlyWitnessWord(page: var PageImage, offset: int, value: uint32) =
    ## Place one complete little-endian control word inside a private immutable input page.
    assert offset >= 0 and offset <= page.bytes.len-4
    for lane in 0..<4:
      page.bytes[offset+lane] = byte((value shr (lane*8)) and 255'u32)

  proc witnessFlatReadOnlyMixedFrames*(program: Program, pc: uint32, report = true) =
    ## Compare direct native entry, exact checked fallback and repaired paid retry on original facts.
    let cycles = GasCycleLimit(100000)
    var prepared = prepareFlatPlan(program, cycles, defaultFlatLimits(), false)
    assert prepared.error == FlatError.None
    let plan = takeValue(prepared)
    let price = blockGas(program, CodeAddress(uint64(pc)), cycles)
    assert price.error == GasError.None and uint64(price.value) > 0
    let blockPrice = uint64(price.value)
    const base = 0x10000'u64
    const span = 5'u64
    const expectedVisits = [2'u64, 1, 1, 3, 2, 1, 1, 0, 1, 0, 0, 1, 0]
    const expectedRefusals = [0'u64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0]

    for scenario in ReadOnlyLoopCase:
      # Every case borrows a fresh RO owner and the same original program operations.
      var readable = PageImage(index: PageIndex(base div 4096), access: PageAccess.ReadOnly)
      var offset = 0
      var words = [10'u32, 20, 0]
      var threshold = 0'u64
      case scenario
      of ReadOnlyLoopCase.NegativeThreshold:
        words = [1'u32, 0xfffffffe'u32, 0]
        threshold = high(uint64)
      of ReadOnlyLoopCase.NegativeLoad:
        words = [0xffffffff'u32, 0, 0]
      of ReadOnlyLoopCase.HighBitLoad:
        words = [0x80000000'u32, 0, 0]
      of ReadOnlyLoopCase.MinimumBound:
        threshold = 0x8000000000000000'u64
      of ReadOnlyLoopCase.MaximumBound:
        words = [0xffffffff'u32, 0, 0]
        threshold = 0x7fffffffffffffff'u64
      of ReadOnlyLoopCase.FirstWidthFault:
        offset = 4094
      of ReadOnlyLoopCase.LaterWidthFault:
        offset = 4090
      else:
        # Remaining funding and changed-address controls use the same three ordered words.
        discard
      if scenario == ReadOnlyLoopCase.FirstWidthFault:
        # The missing high half is supplied only by the later repaired owner.
        readable.bytes[4094] = 10
      elif scenario == ReadOnlyLoopCase.LaterWidthFault:
        readOnlyWitnessWord(readable, 4090, 10)
        readable.bytes[4094] = 20
      else:
        for index, value in words:
          readOnlyWitnessWord(readable, index*4, value)
      let quota = case scenario
        of ReadOnlyLoopCase.ExactQuota: span
        of ReadOnlyLoopCase.MinimumBound: 2*span
        of ReadOnlyLoopCase.PartialQuota: span-1
        of ReadOnlyLoopCase.ZeroQuota: 0'u64
        else: 50'u64
      let gas = case scenario
        of ReadOnlyLoopCase.ExactGas: blockPrice
        of ReadOnlyLoopCase.InsufficientGas: blockPrice-1
        else: blockPrice*20+100
      var info = MachineInfo(pc: CodeAddress(uint64(pc)), gas: MachineGas(gas))
      info.registers[6] = RegisterValue(0x12345678)
      info.registers[7] = RegisterValue(threshold)
      info.registers[10] = RegisterValue(7)
      info.registers[11] = RegisterValue(3)
      info.registers[12] = RegisterValue(base+uint64(offset))
      var native = newFlatFrame(plan, [readable], info)
      var checked = newFlatFrame(plan, [readable], info)
      for frame in [addr native, addr checked]:
        # Resolve both original arms without executing their unrelated outside body.
        let header = flatResolve(frame[], pc)
        assert header != flatStop
        var source = default(FlatSourceInterval)
        var walk = default(FlatSourceSummary)
        assert flatSourceIntervalAt(frame[], header, NativeReadFactLimit, source)
        assert flatWalkCompleteSource(frame[], header, source, walk)
        assert flatUnresolvedBranch[173](frame[], walk.terminal) == walk.terminal
      let proof = buildFlatMixedLoop(native, pc, 1, readOnly = true)
      assert proof.complete and uint64(proof.span) == span and proof.count == 4
      assert proof.price == blockPrice and proof.operations[0].opcode == 129
      assert proof.operations[3].opcode == 173
      assert buildFlatMixedLoop(checked, pc, 1, readOnly = true) == proof
      var corrupted = proof
      corrupted.operations[0].opcode = 120
      assert not corrupted.complete
      corrupted = proof
      corrupted.operations[3].opcode = 171
      assert not corrupted.complete
      assert not nativeMixedLoopReceipt(proof, 257, 0, info.registers).valid
      assert not nativeMixedLoopReceipt(proof, 1, 2, info.registers).valid
      assert not nativeMixedLoopReceipt(proof, 1, NativeMixedLoopExitBit, info.registers).valid
      var boundaryRegisters = info.registers
      boundaryRegisters[7] = RegisterValue(0x8000000000000000'u64)
      boundaryRegisters[6] = RegisterValue(0x7fffffffffffffff'u64)
      assert nativeMixedLoopReceipt(proof, 1, 1, boundaryRegisters).valid
      assert not nativeMixedLoopReceipt(proof, 1, NativeMixedLoopExitBit or 1,
        boundaryRegisters).valid
      boundaryRegisters[7] = RegisterValue(0x7fffffffffffffff'u64)
      boundaryRegisters[6] = RegisterValue(0x8000000000000000'u64)
      assert nativeMixedLoopReceipt(proof, 1, NativeMixedLoopExitBit or 1,
        boundaryRegisters).valid
      assert not nativeMixedLoopReceipt(proof, 1, 1, boundaryRegisters).valid
      var refused = false
      var image = lowerNativeMixedLoop(proof, refused)
      assert image.ready and not refused
      native.mixedWitnessProof = proof
      native.mixedWitnessImage = addr image
      native.handlers[int(proof.header)] = flatMixedLoopEntryWitness
      native.handlers[int(proof.exitHeader)] = flatReadOnlyWitnessExit
      checked.handlers[int(proof.exitHeader)] = flatReadOnlyWitnessExit
      runFlat(native, quota)
      runFlat(checked, quota)
      native.mixedWitnessImage = nil
      assertPaidFramesEqual(native, checked)
      assert native.dirtyIndices.len == 0
      assert native.mixedWitnessVisits == expectedVisits[ord(scenario)]
      assert native.mixedWitnessRefusals == expectedRefusals[ord(scenario)]
      if scenario == ReadOnlyLoopCase.NegativeThreshold:
        assert uint64(native.info.registers[6]) == 0xfffffffffffffffe'u64
      elif scenario == ReadOnlyLoopCase.NegativeLoad:
        assert uint64(native.info.registers[6]) == high(uint64)
      elif scenario == ReadOnlyLoopCase.HighBitLoad:
        assert uint64(native.info.registers[6]) == 0xffffffff80000000'u64
      elif scenario == ReadOnlyLoopCase.ChangedAddress:
        assert uint64(native.info.registers[6]) == 0
        assert uint64(native.info.registers[12]) == base+12
        assert uint64(native.info.registers[11]) == 24
      if scenario in [ReadOnlyLoopCase.FirstWidthFault, ReadOnlyLoopCase.LaterWidthFault]:
        # A failed first uncommitted load preserves every prior complete visit's register state.
        assert native.exit == oracle.StepExit.Fault and native.info.blockCharged
        assert uint64(native.info.pc) == uint64(pc)+1
        assert uint64(native.faultPage) == base+4096
        let complete = expectedVisits[ord(scenario)]
        assert uint64(native.info.registers[12]) == base+uint64(offset)+complete*4
        assert uint64(native.info.registers[11]) == 3+complete*7
        assert uint64(native.info.gas) == gas-(complete+1)*blockPrice
        assert native.remaining == quota-complete*span-2
        let supplied = PageImage(index: PageIndex((base+4096) div 4096),
            access: PageAccess.ReadOnly)
        let nativeMemory = withPage(flatMemorySnapshot(native), supplied)
        let checkedMemory = withPage(flatMemorySnapshot(checked), supplied)
        assert nativeMemory.error == MachineError.None and checkedMemory.error == MachineError.None
        var nativeRetry = prepareFlatMemoryFrame(plan, nativeMemory.value, native.info)
        var checkedRetry = prepareFlatMemoryFrame(plan, checkedMemory.value, checked.info)
        assert nativeRetry.error == FlatError.None and checkedRetry.error == FlatError.None
        var resumed = takeValue(nativeRetry)
        var reference = takeValue(checkedRetry)
        var nativeStream = takeFlatStream(native)
        var checkedStream = takeFlatStream(checked)
        restoreFlatStream(resumed, nativeStream)
        restoreFlatStream(reference, checkedStream)
        resumed.mixedWitnessProof = proof
        resumed.mixedWitnessImage = addr image
        resumed.handlers[int(proof.header)] = flatMixedLoopEntryWitness
        runFlat(resumed, 50)
        runFlat(reference, 50)
        resumed.mixedWitnessImage = nil
        assertPaidFramesEqual(resumed, reference)
        assert uint64(resumed.info.registers[6]) == 0
        assert uint64(resumed.info.registers[12]) == base+4094+8
        assert resumed.dirtyIndices.len == 0
        if report:
          echo "READ_ONLY_RETRY,", ord(scenario), ",", uint64(resumed.info.pc), ",",
            uint64(resumed.info.gas), ",", resumed.remaining
      if report:
        echo "READ_ONLY_FRAME,", ord(scenario), ",", native.mixedWitnessVisits, ",",
          native.mixedWitnessRefusals, ",", uint64(native.info.pc), ",", uint64(native.info.gas),
          ",", native.remaining, ",", uint64(native.faultPage), ",", image.codeBytes

  when defined(pvmSharedAsyncWitness):
    proc witnessFlatReadOnlyScheduling*(program: Program, pc: uint32,
        session: NativeSession, visits: uint32, expectedOffer: bool, stale = false) =
      ## Exercise the isolated loop-only probe with a real checked read segment.
      ## Short observed work, a stale source epoch or an unpermitted lease cannot queue.
      assert visits in 1'u32..1000'u32 and not nativeInvocationUsed(session)
      var admitted = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
      assert admitted.error == FlatError.None
      let plan = takeValue(admitted)
      var readable = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly)
      for index in 0..<int(visits)-1: readOnlyWitnessWord(readable, index*4, 1)
      var info = MachineInfo(pc: CodeAddress(uint64(pc)), gas: MachineGas(1000000))
      info.registers[12] = RegisterValue(16*4096)
      var frame = newFlatFrame(plan, [readable], info)
      frame.nativeSession = session
      frame.mixedProbeWitness = true
      let header = flatResolve(frame, pc)
      var source = default(FlatSourceInterval)
      var walk = default(FlatSourceSummary)
      assert flatSourceIntervalAt(frame, header, NativeReadFactLimit, source)
      assert flatWalkCompleteSource(frame, header, source, walk)
      assert flatUnresolvedBranch[173](frame, walk.terminal) == walk.terminal
      let epoch = nativeEpoch(session)
      let proof = buildFlatMixedLoop(frame, pc, epoch)
      assert proof.complete and mixedLoopDisjoint(session, proof)
      frame.handlers[int(proof.exitHeader)] = flatReadOnlyWitnessExit
      frame.mixedSource = FlatMixedLoopSource(epoch: (if stale: epoch+1 else: epoch), count: 1)
      frame.mixedSource.candidates[0] = pc+1
      let before = nativeStatistics(session)
      runFlat(frame, uint64(visits)*uint64(proof.span)+1)
      assert frame.reason == oracle.StepError.None and frame.info.pc == CodeAddress(
          uint64(plan.facts[int(frame.sites[int(proof.exitHeader)])].pc))
      assert frame.mixedProbe == nil and not nativeInvocationUsed(session)
      assert nativeStatistics(session) == before
      assert (frame.mixedSource.chosenCount == 1) == expectedOffer
      if expectedOffer: assert frame.mixedSource.chosen[0] == pc+1

  proc witnessFlatReadOnlyDiscovery*(program: Program, pcs: openArray[uint32], expected: uint8) =
    ## Both predicate orientations certify individually; one initial read-only candidate bounds the family.
    var admitted = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
    assert admitted.error == FlatError.None
    let runtime = newNativeRuntime()
    var frame = newFlatFrame(takeValue(admitted), [], MachineInfo(gas: MachineGas(1000000)))
    frame.nativeSession = newNativeSession(runtime)
    for pc in pcs:
      let header = flatResolve(frame, pc)
      var source = default(FlatSourceInterval)
      var walk = default(FlatSourceSummary)
      assert flatSourceIntervalAt(frame, header, NativeReadFactLimit, source)
      assert flatWalkCompleteSource(frame, header, source, walk)
      assert flatUnresolvedBranch[173](frame, walk.terminal) == walk.terminal
      assert buildFlatMixedLoop(frame, pc, nativeEpoch(frame.nativeSession)).complete
    assert frame.mixedSource.count == expected and frame.mixedSource.checks == expected
    if expected != 0: assert frame.mixedSource.candidates[0] == pcs[0]+1

  proc witnessFlatReadOnlyOrientation*(program: Program, pc: uint32): uint64 =
    ## Compare both loaded-operand orientations, including negative S32 values, with original checked work.
    let proof = witnessFlatReadOnlyMixedSource(program, pc)
    let read = proof.operations[0]
    let advance = proof.operations[int(proof.count)-2]
    let branch = proof.operations[int(proof.count)-1]
    assert read.opcode == 129 and advance.opcode == 149 and branch.opcode == 173
    assert read.immediate <= 65536'u64
    assert advance.immediate in [4'u64, 8'u64] and advance.slots.bIndex == read.slots.bIndex
    let loadedRight = branch.slots.bIndex == read.slots.aIndex
    let bound = if loadedRight: branch.slots.aIndex else: branch.slots.bIndex
    assert bound != read.slots.aIndex and bound != read.slots.bIndex
    var refused = false
    var image = lowerNativeMixedLoop(proof, refused)
    assert image.ready and not refused
    result = image.codeBytes
    for negative in [false, true]:
      var admitted = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
      assert admitted.error == FlatError.None
      let plan = takeValue(admitted)
      var page = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly)
      let first = if negative:
          (if loadedRight: 0'u32 else: 0xfffffffe'u32)
        else: (if loadedRight: 1'u32 else: 0'u32)
      let last = if negative: 0xffffffff'u32 else: (if loadedRight: 0'u32 else: 1'u32)
      readOnlyWitnessWord(page, 0, first)
      readOnlyWitnessWord(page, int(advance.immediate), last)
      var info = MachineInfo(pc: CodeAddress(uint64(pc)), gas: MachineGas(1000000))
      info.registers[read.slots.bIndex] = RegisterValue(65536'u64-read.immediate)
      info.registers[bound] = RegisterValue(if negative: high(uint64)
        else: (if loadedRight: 0'u64 else: 1'u64))
      var native = newFlatFrame(plan, [page], info)
      var checked = newFlatFrame(plan, [page], info)
      for frame in [addr native, addr checked]:
        let header = flatResolve(frame[], pc)
        var source = default(FlatSourceInterval)
        var walk = default(FlatSourceSummary)
        assert flatSourceIntervalAt(frame[], header, NativeReadFactLimit, source)
        assert flatWalkCompleteSource(frame[], header, source, walk)
        assert flatUnresolvedBranch[173](frame[], walk.terminal) == walk.terminal
        assert buildFlatMixedLoop(frame[], pc, 1) == proof
        frame[].handlers[int(proof.exitHeader)] = flatReadOnlyWitnessExit
      native.mixedWitnessProof = proof
      native.mixedWitnessImage = addr image
      native.handlers[int(proof.header)] = flatMixedLoopEntryWitness
      runFlat(native, 50)
      runFlat(checked, 50)
      native.handlers[int(proof.header)] = flatCharge
      native.mixedWitnessImage = nil
      assertPaidFramesEqual(native, checked)
      assert native.mixedWitnessVisits == 2
