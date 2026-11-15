# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included test-only source-binding, scoped overlay and exact quota/predecessor controls.

when declared(FlatFrame):
  proc fusionWitnessOperations(session: NativeSession): uint64 {.noinline.} =
    ## Keep the established NIM-005 counter observation boundary across mutable frame calls.
    nativeOperationCount(session)

  func fusionWitnessReservedEnd(frame: FlatFrame): uint32 =
    ## Decode only an outstanding paid reservation; unpaid stale scratch grants no source extent.
    if not frame.info.blockCharged: return 0
    let reservation = frame.reservation
    if (reservation and flatReservationHeaderFlag) == 0: return reservation
    let header = reservation and not flatReservationHeaderFlag
    assert int(header) < frame.sites.len and int(header) < frame.arguments.len
    frame.sites[int(header)]+frame.arguments[int(header)].y

  proc assertFusionFrame(actual, expected: FlatFrame, context: string = "") =
    ## Compare the complete stopped CPU, attempts, fault, memory and dirty state before reuse.
    assert actual.info == expected.info, "composition CPU " & context
    assert actual.reason == expected.reason and actual.exit == expected.exit, "composition exit " & context
    assert actual.remaining == expected.remaining and fusionWitnessReservedEnd(actual) ==
        fusionWitnessReservedEnd(expected), "composition outstanding reservation " & context
    assert uint64(actual.faultPage) == uint64(expected.faultPage) and actual.stoppedAt ==
        expected.stoppedAt, "composition stopped coordinate " & context
    assert actual.attemptedExit == expected.attemptedExit, "composition attempted exit " & context
    assert uint64(actual.hostCall) == uint64(expected.hostCall) and actual.hostReady ==
        expected.hostReady, "composition host boundary " & context
    assert actual.dirtyPages == expected.dirtyPages and actual.dirtyIndices ==
        expected.dirtyIndices, "composition dirty state " & context
    assert actual.rw.len == expected.rw.len, "composition memory extent " & context
    for index in 0..<actual.rw.len: assert actual.rw[index] == expected.rw[index],
        "composition memory byte " & context
    assert actual.barrier == flatStop and actual.savedHandler == nil,
        "composition barrier cleanup " & context
    assert actual.fusionImage == nil and actual.fusionBlocks == nil and actual.fusionContext == nil,
        "composition image cleanup " & context
    assert actual.fusionSlots == nil and actual.fusionReceipts == nil,
        "composition receipt cleanup " & context
    for index in 0..<actual.handlers.len: assert actual.handlers[index] != flatFusionEntry,
        "composition handler cleanup " & context

  proc witnessFlatFusionComposition*(program: Program, secondPc: uint32, branch: byte,
      runtime: NativeRuntime) =
    ## Admit original source, warm real checked workers, reject altered identities/operands/targets,
    ## then exercise the same borrowed-image scope as production at partial gas and source quotas.
    var admitted = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
    assert admitted.error == FlatError.None
    let plan = takeValue(admitted)
    var page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
    page.bytes[0] = 0x5a
    var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000000))
    for index in 0..12: info.registers[index] = RegisterValue(0x1234567800000000'u64+uint64(index))
    info.registers[2] = RegisterValue(0)
    info.registers[3] = RegisterValue(0xffff0000'u64)
    let session = newNativeSession(runtime)
    for warm in [false, true]:
      # Both workers use genuine resolved branch capabilities; cold/hot body identities are distinct.
      var native = newFlatFrame(plan, [page], info)
      var checked = newFlatFrame(plan, [page], info)
      var first, second = 0'u32
      for frame in [addr native, addr checked]:
        first = flatResolve(frame[], 0)
        second = flatResolve(frame[], secondPc)
        assert first != flatStop and second != flatStop
        var a, b = default(FlatSourceInterval)
        var aWalk, bWalk = default(FlatSourceSummary)
        assert flatSourceIntervalAt(frame[], first, NativeReadFactLimit, a)
        assert flatSourceIntervalAt(frame[], second, NativeReadFactLimit, b)
        assert flatWalkCompleteSource(frame[], first, a, aWalk)
        assert flatWalkCompleteSource(frame[], second, b, bWalk)
        if branch == 83: assert flatUnresolvedBranch[83](frame[], aWalk.terminal) == aWalk.terminal
        else: assert flatUnresolvedBranch[88](frame[], aWalk.terminal) == aWalk.terminal
        assert flatUnresolvedBranch[81](frame[], bWalk.terminal) == bWalk.terminal
        frame[].remaining = 100
        let adjacent = frame[].handlers[int(second)]
        discard adjacent(frame[], second)
        if warm:
          let charge = frame[].handlers[int(first)]
          discard charge(frame[], first)
        resetFlatFrame(frame[], info)
        frame[].remaining = 0
      let firstOriginal = native.handlers[int(first)]
      let secondOriginal = native.handlers[int(second)]
      assert firstOriginal == flatCharge and secondOriginal == flatChargedAdjacent[false]
      if branch == 83:
        # Positive controls must exercise the intended combined identity, not an ordinary paired worker.
        if warm: assert native.handlers[int(first+1)] == flatFusedRegisterBranch[131, 83]
        else: assert native.handlers[int(first+1)] == flatRegisterBranchCold[131, 83]
      else:
        # The folded leading source noop keeps the physical combined body at the same original node.
        if warm: assert native.handlers[int(first+1)] == flatFusedRegisterBranch[131, 88]
        else: assert native.handlers[int(first+1)] == flatRegisterBranchCold[131, 88]
      var blocks: seq[NativeFusionBlock] = @[]
      for header in [first, second]:
        var item = default(NativeFusionBlock)
        assert bindFlatFusion(native, header, item), "original composed source must bind"
        blocks.add(item)
      let body = first+1
      let terminal = blocks[0].terminal
      let originalBody = native.handlers[int(body)]
      let originalTerminal = native.handlers[int(terminal)]
      let originalArgs = native.arguments[int(terminal)]
      let originalSite = native.sites[int(terminal)]
      let adjacentTerminal = blocks[1].terminal
      let adjacentTerminalWorker = native.handlers[int(adjacentTerminal)]
      let adjacentTerminalArgs = native.arguments[int(adjacentTerminal)]
      for mutation in 0..10:
        # Each damaged capability is independent; binding never executes or mutates guest state.
        case mutation
        of 0: native.handlers[int(first)] = flatChargedAdjacent[false]
        of 1: native.handlers[int(body)] = flatRegisterPair[149]
        of 2:
          if branch == 83: native.handlers[int(body)] = flatRegisterBranchCold[131, 88]
          else: native.handlers[int(body)] = flatRegisterBranchCold[131, 83]
        of 3: native.arguments[int(terminal)].x = originalArgs.x xor 1
        of 4: native.arguments[int(terminal)].y = first
        of 5: native.sites[int(terminal)] = originalSite-1
        of 6: native.handlers[int(terminal)] = flatBudget
        of 7: native.arguments[int(second)].x += 1
        of 8: native.arguments[int(second)].y = 1
        of 9: native.handlers[int(adjacentTerminal)] = flatBudget
        else: native.arguments[int(adjacentTerminal)].x = adjacentTerminalArgs.x xor 1
        let target = if mutation >= 7: second else: first
        var refused = default(NativeFusionBlock)
        assert not bindFlatFusion(native, target, refused),
            "damaged composed source must refuse: " & $mutation
        assert native.info == info and native.remaining == 0 and native.dirtyIndices.len == 0
        native.handlers[int(first)] = firstOriginal
        native.handlers[int(body)] = originalBody
        native.handlers[int(terminal)] = originalTerminal
        native.arguments[int(terminal)] = originalArgs
        native.sites[int(terminal)] = originalSite
        native.arguments[int(second)].x = blocks[1].price
        native.arguments[int(second)].y = blocks[1].span
        native.handlers[int(adjacentTerminal)] = adjacentTerminalWorker
        native.arguments[int(adjacentTerminal)] = adjacentTerminalArgs
      var image = lowerNativeFusion(blocks)
      assert image.ready and nativeFusionDispatchEntry(image, 0) and nativeFusionDispatchEntry(
          image, 1), "composition graph must expose both linked entries"
      for header in [first, second]:
        # A quota barrier keeps its live slot while the fusion scope restores the actual saved predecessor.
        let original = native.handlers[int(header)]
        native.handlers[int(header)] = flatBudget
        native.barrier = header
        native.savedHandler = flatFusionEntry
        restoreFlatTemporaryHandler(native, header, flatFusionEntry, original)
        assert native.reason == oracle.StepError.None and native.handlers[int(header)] == flatBudget
        assert native.savedHandler == original, "composition restores specialized saved quota predecessor"
        native.handlers[int(header)] = original
        native.barrier = flatStop
        native.savedHandler = nil
        # A different saved owner must refuse without overwriting either live or retained identity.
        native.handlers[int(header)] = flatBudget
        native.barrier = header
        native.savedHandler = original
        restoreFlatTemporaryHandler(native, header, flatFusionEntry, original)
        assert native.reason == oracle.StepError.BackendFailure
        assert native.handlers[int(header)] == flatBudget and native.savedHandler == original
        native.handlers[int(header)] = original
        native.barrier = flatStop
        native.savedHandler = nil
        native.reason = oracle.StepError.None
      native.nativeSession = session
      for initial in [0'u64, 0xffffffff'u64, 0x7fffffff'u64]:
        for gas in [0'u64, blocks[0].price-1, blocks[0].price,
            blocks[0].price+blocks[1].price-1, 1000000'u64]:
          for quota in 0'u64..12'u64:
            # Every original body/terminal boundary remains addressable, including an ADD before its branch.
            var cpu = info
            cpu.registers[2] = RegisterValue(initial)
            cpu.gas = MachineGas(gas)
            resetFlatFrame(native, cpu)
            resetFlatFrame(checked, cpu)
            native.fusionWitnessImage = addr image
            native.fusionWitnessBlocks = addr blocks
            beginNativeInvocation(session, quota)
            let before = fusionWitnessOperations(session)
            runFlat(native, quota)
            let after = fusionWitnessOperations(session)
            finishNativeInvocation(session, 0)
            native.fusionWitnessImage = nil
            native.fusionWitnessBlocks = nil
            runFlat(checked, quota)
            assertFusionFrame(native, checked, "branch=" & $branch & " warm=" & $warm & " input=" &
                $initial & " gas=" & $gas & " quota=" & $quota)
            assert native.handlers[int(first)] == firstOriginal
            assert native.handlers[int(second)] == secondOriginal
            if initial == 0 and gas == 1000000 and quota == 12:
              # Both admitted blocks, including the formerly specialized header, actually execute natively.
              assert after-before == uint64(blocks[0].span+blocks[1].span), "composition actual native work"
      # Stop after the ADD but before its original branch, then move the paid continuation to a fresh frame.
      resetFlatFrame(native, info)
      resetFlatFrame(checked, info)
      native.fusionWitnessImage = addr image
      native.fusionWitnessBlocks = addr blocks
      let partialQuota = uint64(blocks[0].span)-1
      beginNativeInvocation(session, partialQuota)
      runFlat(native, partialQuota)
      finishNativeInvocation(session, 0)
      native.fusionWitnessImage = nil
      native.fusionWitnessBlocks = nil
      runFlat(checked, partialQuota)
      assertFusionFrame(native, checked)
      assert native.reason == oracle.StepError.StepLimitExceeded and native.info.blockCharged
      assert uint64(native.info.registers[2]) == 1 and uint64(native.info.gas) == 1000000-blocks[0].price
      assert native.info.pc == CodeAddress(uint64(native.plan.facts[int(blocks[0].first)+int(blocks[
          0].span)-1].pc))
      let snapshot = flatMemorySnapshot(native)
      let baseline = flatMemorySnapshot(checked)
      var resumedResult = prepareFlatMemoryFrame(plan, snapshot, native.info)
      var comparedResult = prepareFlatMemoryFrame(plan, baseline, checked.info)
      assert resumedResult.error == FlatError.None and comparedResult.error == FlatError.None
      var reused = takeValue(resumedResult)
      var compared = takeValue(comparedResult)
      # A retained code-only owner must contain neither borrowed image pointers nor temporary handlers.
      var retained = takeFlatStream(native)
      var control = takeFlatStream(checked)
      restoreFlatStream(reused, retained)
      restoreFlatStream(compared, control)
      assert reused.handlers[int(first)] == firstOriginal and reused.handlers[int(second)] == secondOriginal
      assert reused.fusionImage == nil and reused.fusionWitnessImage == nil and
          reused.fusionWitnessBlocks == nil
      reused.nativeSession = session
      reused.fusionWitnessImage = addr image
      reused.fusionWitnessBlocks = addr blocks
      beginNativeInvocation(session, 12)
      let before = fusionWitnessOperations(session)
      runFlat(reused, 12)
      let after = fusionWitnessOperations(session)
      finishNativeInvocation(session, 0)
      reused.fusionWitnessImage = nil
      reused.fusionWitnessBlocks = nil
      runFlat(compared, 12)
      assertFusionFrame(reused, compared)
      assert uint64(reused.info.registers[2]) == 1 and after-before == uint64(blocks[1].span)
      assert reused.handlers[int(first)] == firstOriginal and reused.handlers[int(second)] == secondOriginal
