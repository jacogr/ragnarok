# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private source and execution controls for the original paid mixed-loop continuation.

when declared(FlatFrame) and defined(pvmPaidMixedLoopWitness):
  proc assertPaidFramesEqual(native, checked: FlatFrame) =
    assert native.info == checked.info and native.reason == checked.reason and native.exit == checked.exit
    assert uint64(native.faultPage) == uint64(checked.faultPage)
    assert native.remaining == checked.remaining and native.reservation == checked.reservation
    assert native.stoppedAt == checked.stoppedAt and native.attemptedExit == checked.attemptedExit
    assert native.dirtyPages == checked.dirtyPages and native.dirtyIndices == checked.dirtyIndices
    let left = flatMemorySnapshot(native)
    let right = flatMemorySnapshot(checked)
    let leftIndices = pageIndices(left)
    let rightIndices = pageIndices(right)
    assert leftIndices.error == MachineError.None and rightIndices.error == MachineError.None
    assert leftIndices.value.len == rightIndices.value.len
    for slot, page in leftIndices.value:
      assert uint32(page) == uint32(rightIndices.value[slot])
      let a = pageImage(left, page)
      let b = pageImage(right, page)
      assert a.error == MachineError.None and b.error == MachineError.None
      assert a.value.access == b.value.access and a.value.bytes == b.value.bytes

  proc witnessFlatPaidMixedLoop*(program: Program, pc: uint32, base, wordAddress,
      readBase: uint64, report: bool = true) =
    ## Compare true native entries to original checked workers before and after repairing a fault.
    let cycles = GasCycleLimit(100000)
    var prepared = prepareFlatPlan(program, cycles, defaultFlatLimits(), false)
    assert prepared.error == FlatError.None
    let plan = takeValue(prepared)
    let price = blockGas(program, CodeAddress(uint64(pc)), cycles)
    assert price.error == GasError.None and uint64(price.value) > 0
    let blockPrice = uint64(price.value)
    let runtime = newNativeRuntime()
    try:
      assert start(runtime)
    except:
      assert false, "paid witness native worker failed to start"
    let span = 10'u64
    let firstWordPage = wordAddress div 4096
    let lastWordPage = (wordAddress+3) div 4096
    assert lastWordPage == firstWordPage+1 and firstWordPage shr 6 != lastWordPage shr 6
    var first = PageImage(index: PageIndex(base div 4096), access: PageAccess.ReadWrite)
    first.bytes[3] = 0x80
    var wordStart = PageImage(index: PageIndex(firstWordPage), access: PageAccess.ReadWrite)
    wordStart.bytes[4094] = 0x44
    wordStart.bytes[4095] = 0x55
    var wordEnd = PageImage(index: PageIndex(lastWordPage), access: PageAccess.ReadWrite)
    wordEnd.bytes[0] = 0x66
    wordEnd.bytes[1] = 0x77
    let read = PageImage(index: PageIndex(readBase div 4096), access: PageAccess.ReadOnly)

    for scenario in 0..9:
      let pages = if scenario == 7: @[first, wordStart, read] else: @[first, wordStart, wordEnd, read]
      let visits = if scenario in [0, 5]: 2'u64 else: 1'u64
      let gas = if scenario == 9: blockPrice-1 else: visits*blockPrice+10
      let quota = if scenario == 8: 3'u64 else: visits*span+1
      var info = MachineInfo(pc: CodeAddress(uint64(pc)), gas: MachineGas(gas))
      info.registers[0] = RegisterValue(0xa5)
      info.registers[5] = RegisterValue(base)
      info.registers[6] = RegisterValue(readBase)
      let readOffset = case scenario
        of 4: 4092'u64
        of 5: 4088'u64
        else: 4084'u64
      info.registers[9] = RegisterValue(readBase+readOffset)
      info.registers[12] = RegisterValue(base+visits)
      var native = newFlatFrame(plan, pages, info)
      var checked = newFlatFrame(plan, pages, info)
      for frame in [addr native, addr checked]:
        let header = flatResolve(frame[], pc)
        assert header != flatStop
        var interval = default(FlatSourceInterval)
        var walk = default(FlatSourceSummary)
        assert flatSourceIntervalAt(frame[], header, NativeReadFactLimit, interval)
        assert flatWalkCompleteSource(frame[], header, interval, walk)
        assert flatUnresolvedBranch[171](frame[], walk.terminal) == walk.terminal
        if scenario != 6: flatMarkStore[1](frame[], base)
        if scenario notin [2, 3]: flatMarkStore[1](frame[], wordAddress)
        if scenario notin [1, 3, 7]: flatMarkStore[1](frame[], wordAddress+3)

      let proof = buildFlatMixedLoop(native, pc, 1, allowPaid = true)
      assert proof.complete and uint64(proof.span) == span and proof.count == 8 and proof.price == blockPrice
      assert proof.paidGuards == 0x2f'u32
      assert not buildFlatMixedLoop(native, pc, 1, allowPaid = false).complete
      var corrupted = proof
      corrupted.paidGuards = corrupted.paidGuards xor 1
      assert not corrupted.complete
      let rawGuard = 3'u32 shl NativeMixedLoopGuardShift
      assert nativeMixedLoopReceipt(proof, 1, rawGuard, info.registers).paid
      assert nativeMixedLoopReceipt(proof, 256, 256, info.registers).valid
      assert not nativeMixedLoopReceipt(proof, 0, 0, info.registers).valid
      assert not nativeMixedLoopReceipt(proof, 1, rawGuard or 1, info.registers).valid
      assert not nativeMixedLoopReceipt(proof, 1, rawGuard or NativeMixedLoopExitBit,
          info.registers).valid
      assert not nativeMixedLoopReceipt(proof, 1, NativeMixedLoopExitBit, info.registers).valid
      assert not nativeMixedLoopReceipt(proof, 1, 5'u32 shl NativeMixedLoopGuardShift,
          info.registers).valid
      assert not nativeMixedLoopReceipt(proof, 1, 8'u32 shl NativeMixedLoopGuardShift,
          info.registers).valid
      assert not nativeMixedLoopReceipt(proof, 1, 1'u32 shl 20, info.registers).valid

      var refused = false
      var image = lowerNativeMixedLoop(proof, refused)
      assert image.ready and not refused
      var pair = default(FlatMixedPairWitness)
      pair.proofs[1] = proof
      pair.images[1] = addr image
      native.mixedPair = addr pair
      native.handlers[int(proof.header)] = flatMixedPairEntry
      let session = newNativeSession(runtime)
      beginNativeInvocation(session, quota)
      native.nativeSession = session
      runFlat(native, quota)
      native.handlers[int(proof.header)] = flatCharge
      native.mixedPair = nil
      finishNativeInvocation(session, 0)
      runFlat(checked, quota)
      assertPaidFramesEqual(native, checked)
      let observed = pair.counts[1]
      let expectedVisits = [2'u64, 0, 0, 0, 0, 1, 0, 0, 0, 0]
      let expectedPaid = [0'u64, 1, 1, 1, 1, 1, 1, 1, 0, 0]
      let expectedPrefix = [0'u64, 7, 7, 7, 4, 4, 2, 7, 0, 0]
      assert observed.visits == expectedVisits[scenario] and observed.paid == expectedPaid[scenario]
      assert observed.operations == expectedVisits[scenario]*span+expectedPrefix[scenario]
      assert observed.branches == uint64(ord(scenario in [0, 5]))
      assert observed.repeatedHeaders == uint64(ord(scenario == 0))
      let owner = nativeOwnerStatistics(session)
      assert owner[0] == 0 and owner[1] == uint64(ord(observed.operations > 0)) and
        owner[2] == observed.operations and owner[3] == 0
      let control = nativeControlStatistics(session)
      assert control.branchCalls == observed.branches and control.headerCalls ==
          observed.repeatedHeaders
      if observed.paid != 0:
        assert observed.lastGuardOrdinal == proof.first+uint32(expectedPrefix[scenario])
        assert observed.lastGuardPc == native.plan.facts[int(observed.lastGuardOrdinal)].pc
      if scenario == 8:
        assert native.reason == oracle.StepError.StepLimitExceeded
        assert uint64(native.info.pc) == uint64(native.plan.facts[int(proof.first)+3].pc)
        assert native.plan.facts[int(proof.first)+3].opcode == 2
      if scenario == 9:
        assert native.exit == oracle.StepExit.OutOfGas and uint64(native.info.gas) == gas
      if scenario in [0, 1, 2, 3, 6]:
        let expected = if scenario == 0: 0xffffffff8000a5a5'u64 else: 0xffffffff800000a5'u64
        assert uint64(native.info.registers[3]) == expected
        let finalWord = load(flatMemorySnapshot(native), MemoryAddress(wordAddress), AccessWidth(4))
        assert finalWord.error == MachineError.None and uint64(finalWord.value) == (expected and 0xffffffff'u64)
      if scenario in [4, 5, 7]:
        assert native.exit == oracle.StepExit.Fault and native.info.blockCharged
        assert uint64(native.info.pc) == uint64(observed.lastGuardPc)
        let attempted = expectedVisits[scenario]*span+expectedPrefix[scenario]+1
        assert native.remaining == quota-attempted
        assert uint64(native.info.gas) == gas-(expectedVisits[scenario]+1)*blockPrice
        let beforeRepair = flatMemorySnapshot(native)
        let early = load(beforeRepair, MemoryAddress(base+expectedVisits[scenario]), AccessWidth(1))
        assert early.error == MachineError.None and uint64(early.value) == 0xa5
        if scenario == 7:
          let untouched = load(beforeRepair, MemoryAddress(wordAddress), AccessWidth(2))
          assert untouched.error == MachineError.None and uint64(untouched.value) == 0x5544
        let expectedFault = if scenario == 7: (lastWordPage shl 12) else: readBase+4096
        assert uint64(native.faultPage) == expectedFault
        let supplied = if scenario == 7: wordEnd else:
          PageImage(index: PageIndex(expectedFault div 4096), access: PageAccess.ReadOnly)
        let nativeRepair = withPage(beforeRepair, supplied)
        let checkedRepair = withPage(flatMemorySnapshot(checked), supplied)
        assert nativeRepair.error == MachineError.None and checkedRepair.error == MachineError.None
        var nativeRetry = prepareFlatMemoryFrame(plan, nativeRepair.value, native.info)
        var checkedRetry = prepareFlatMemoryFrame(plan, checkedRepair.value, checked.info)
        assert nativeRetry.error == FlatError.None and checkedRetry.error == FlatError.None
        var resumed = takeValue(nativeRetry)
        var reference = takeValue(checkedRetry)
        var nativeStream = takeFlatStream(native)
        var checkedStream = takeFlatStream(checked)
        restoreFlatStream(resumed, nativeStream)
        restoreFlatStream(reference, checkedStream)
        let suffix = span-expectedPrefix[scenario]
        runFlat(resumed, suffix+1)
        runFlat(reference, suffix+1)
        assertPaidFramesEqual(resumed, reference)
        let exitPc = resumed.plan.facts[int(resumed.sites[int(proof.exitHeader)])].pc
        let exitPrice = blockGas(program, CodeAddress(uint64(exitPc)), cycles)
        assert exitPrice.error == GasError.None
        assert uint64(resumed.info.gas)+uint64(exitPrice.value) ==
          gas-(expectedVisits[scenario]+1)*blockPrice
        let finalWord = load(flatMemorySnapshot(resumed), MemoryAddress(wordAddress), AccessWidth(4))
        let expectedWord = if scenario == 5: 0x8000a5a5'u64 else: 0x800000a5'u64
        assert finalWord.error == MachineError.None and uint64(finalWord.value) == expectedWord
      if report:
        # Maintained unit goldens stay portable; private qualification retains exact receipts.
        echo "MIXED_PAID_FRAME,", scenario, ",", observed.visits, ",", observed.paid, ",",
          observed.operations, ",", observed.branches, ",", observed.repeatedHeaders, ",",
          observed.lastGuardPc, ",", uint64(native.faultPage)
    assert close(runtime)
