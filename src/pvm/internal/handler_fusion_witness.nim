# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included test-only source-binding, scoped overlay and exact quota/predecessor controls.

when declared(FlatFrame):
  proc witnessFlatFusionSampling*() =
    ## Late hot headers must displace cold collisions without duplicate keys or invented observations.
    const headers = [0'u32, 987, 2584, 3571, 4181]
    let bucket = ((headers[0]+1)*0x9e3779b9'u32) shr 22
    for header in headers:
      assert ((header+1)*0x9e3779b9'u32) shr 22 == bucket
    for scenario in 0..1:
      var probe = FlatFusionProbe(down: 1, seed: 0)
      for index in 0..3:
        # Distinct genuine observations fill one bucket, with a hole before a live key after cancellation.
        let repeats = if scenario == 0 or index == 0: 1 else: (if index == 1: 5 else: 20)
        for repeat in 0..<repeats: sampleFlatFusion(probe, headers[index])
      if scenario == 0:
        # The original first-arrival table dropped every observation of this later hot header.
        for repeat in 0..<16: sampleFlatFusion(probe, headers[4])
      else:
        # Cancellation opens the first slot; lookup must still find the existing second key.
        sampleFlatFusion(probe, headers[4])
        sampleFlatFusion(probe, headers[1])
      var seen = default(array[5, uint32])
      var total = 0'u64
      for sample in probe.samples:
        if sample.token == 0:
          assert sample.count == 0
        else:
          assert sample.count != 0
          total += uint64(sample.count)
          for index in 0..<headers.len:
            if sample.token == headers[index]+1:
              inc seen[index]
              if scenario == 0 and index == 4: assert sample.count in 4'u32..16'u32
              if scenario == 1 and index == 1: assert sample.count in 1'u32..6'u32
      for count in seen: assert count <= 1, "sampling never duplicates a source-header key"
      assert total <= uint64(probe.taken), "retained counts are conservative source observations"
      if scenario == 0: assert seen[4] == 1, "late hot source survives a full cold bucket"
      else: assert seen[1] == 1

  proc witnessFlatFusionSourceLimit*(program: Program, accepted: bool) =
    ## Bound original work, including folded noops; an oversized complete block leaves output intact.
    var admitted = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
    assert admitted.error == FlatError.None
    let plan = takeValue(admitted)
    var source = FusionSourceBlock(start: CodeAddress(77), price: 123)
    let before = source
    assert decodeFusionSource(plan, CodeAddress(0), source) == accepted
    if accepted:
      # Both boundary fixtures have one real body operation and one branch terminal.
      assert source.span == NativeReadFactLimit and source.bodyCount == 1
    else:
      assert source == before
    assert plan.facts.len == 0 and plan.pricePcs.len == 0

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

  proc witnessFlatFusionSuccessorReserve*(program: Program, runtime: NativeRuntime) =
    ## Exercise a full ranking with an unsampled connector through real checked and native dispatch.
    const connector = NativeFusionBlockLimit
    var admitted = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
    assert admitted.error == FlatError.None, "successor plan admission"
    let plan = takeValue(admitted)
    let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000000))
    var frame = newFlatFrame(plan, [], info)
    var checked = newFlatFrame(plan, [], info)
    var headers = default(array[connector+1, uint32])
    for control in [addr frame, addr checked]:
      # The interpreter control uses the same materialization order for physical stop coordinates.
      for index in 0..connector:
        headers[index] = flatResolve(control[], uint32(6*index))
        assert headers[index] != flatStop, "successor source header " & $index
      for header in headers:
        # Resolve genuine checked edges without using their results to choose the samples.
        var source = default(FlatSourceInterval)
        var summary = default(FlatSourceSummary)
        assert flatSourceIntervalAt(control[], header, NativeReadFactLimit, source), "successor source interval"
        assert flatWalkCompleteSource(control[], header, source, summary), "successor complete source"
        assert control[].handlers[int(summary.terminal)] == flatJump[40], "successor unresolved edge"
        assert flatJump[40](control[], summary.terminal) != flatStop, "successor checked edge"
    var probe = FlatFusionProbe(taken: 4096)
    for index in 0..<connector:
      probe.samples[index] = FlatFusionSample(token: headers[index]+1, count: 4)
    probe.samples[0].count = 8
    let original = frame.handlers[int(headers[connector])]
    frame.handlers[int(headers[connector])] = flatBudget
    var ranked = selectFlatFusion(frame, probe)
    assert ranked.len == connector and ranked[^1].header == headers[connector-1],
        "a refused successor leaves the ranked tail intact"
    assert ranked[0].targets[0] == headers[connector], "the rank-only image retains the original edge"
    frame.handlers[int(headers[connector])] = original
    var linked = selectFlatFusion(frame, probe)
    assert linked.len == connector and linked[0].header == headers[0], "successor graph keeps its hot root"
    var connectors = 0
    for item in linked:
      assert item.header != headers[connector-1], "the connector replaces only the last ranked block"
      if item.header == headers[connector]: inc connectors
    assert connectors == 1, "the graph includes one unsampled connector"

    let session = newNativeSession(runtime)
    frame.nativeSession = session
    for blocks in [addr ranked, addr linked]:
      var image = lowerNativeFusion(blocks[])
      assert image.ready, "successor graph must lower"
      for quota in 0'u64..8'u64:
        # A linked successor keeps its original gas and attempt boundaries at partial quotas.
        resetFlatFrame(frame, info)
        resetFlatFrame(checked, info)
        frame.fusionWitnessImage = addr image
        frame.fusionWitnessBlocks = blocks
        beginNativeInvocation(session, quota)
        let before = nativeOwnerStatistics(session)
        runFlat(frame, quota)
        let after = nativeOwnerStatistics(session)
        finishNativeInvocation(session, 0)
        frame.fusionWitnessImage = nil
        frame.fusionWitnessBlocks = nil
        runFlat(checked, quota)
        assertFusionFrame(frame, checked, "successor reserve quota=" & $quota)
        if quota == 8:
          assert uint64(frame.info.registers[2]) == 3 and frame.exit == oracle.StepExit.Host,
              "three original adds reach the checked host boundary"
          if blocks == addr ranked:
            assert after[1]-before[1] == 2 and after[2]-before[2] == 4,
                "the ranked graph crosses two native entry boundaries"
          else:
            assert after[1]-before[1] == 1 and after[2]-before[2] == 6,
                "the reserved graph crosses one native entry boundary"

  proc witnessFlatFusionComposition*(program: Program, secondPc: uint32, branch: byte,
      runtime: NativeRuntime) =
    ## Admit original source, warm real checked workers, reject altered identities/operands/targets,
    ## then exercise the same borrowed-image scope as production at partial gas and source quotas.
    var admitted = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
    assert admitted.error == FlatError.None
    let plan = takeValue(admitted)
    assert plan.facts.len == 0 and plan.pricePcs.len == 0
    var firstSource, secondSource = default(FusionSourceBlock)
    assert decodeFusionSource(plan, CodeAddress(0), firstSource)
    assert decodeFusionSource(plan, CodeAddress(uint64(secondPc)), secondSource)
    assert plan.facts.len == 0 and plan.pricePcs.len == 0,
        "source IR does not materialize a checked catalogue"
    var untouched = firstSource
    for invalid in [CodeAddress(1), CodeAddress(high(uint64))]:
      # Neither an interior instruction/operand nor an out-of-range PC is a complete block entry.
      assert not decodeFusionSource(plan, invalid, untouched) and untouched == firstSource
    var page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
    page.bytes[0] = 0x5a
    var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000000))
    for index in 0..12: info.registers[index] = RegisterValue(0x1234567800000000'u64+uint64(index))
    info.registers[2] = RegisterValue(0)
    info.registers[3] = RegisterValue(0xffff0000'u64)
    let session = newNativeSession(runtime)
    block reversePlacement:
      # Resolve the later source block first: logical ordinals/edges cannot depend on physical order.
      var reversed = newFlatFrame(plan, [page], info)
      let later = flatResolve(reversed, secondPc)
      let earlier = flatResolve(reversed, 0)
      assert later != flatStop and earlier != flatStop and later < earlier
      var reconstructed = default(FusionSourceBlock)
      assert decodeFusionSource(reversed.plan, CodeAddress(0), reconstructed) and
          reconstructed == firstSource
      assert decodeFusionSource(reversed.plan, CodeAddress(uint64(secondPc)), reconstructed) and
          reconstructed == secondSource
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
      var reconstructed = default(FusionSourceBlock)
      assert decodeFusionSource(native.plan, CodeAddress(0), reconstructed) and reconstructed == firstSource
      assert decodeFusionSource(native.plan, CodeAddress(uint64(secondPc)), reconstructed) and
          reconstructed == secondSource
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
        var reconstructed = default(FusionSourceBlock)
        assert decodeFusionSource(native.plan, CodeAddress(0), reconstructed) and reconstructed == firstSource
        assert decodeFusionSource(native.plan, CodeAddress(uint64(secondPc)), reconstructed) and
            reconstructed == secondSource
        var refused = blocks[0]
        let beforeRefusal = refused
        assert not bindFlatFusion(native, target, refused),
            "damaged composed source must refuse: " & $mutation
        assert refused == beforeRefusal, "binding refusal leaves its output untouched"
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
      if branch == 88:
        # A folded noop has no physical node, but its source geometry still belongs to the proof.
        let ordinal = int(blocks[0].first)
        var original = default(FlatFact)
        assert tryReadFlatFact(native, ordinal, original)
        var damaged = original
        inc damaged.next
        assert writeMetadata(native.plan.facts, ordinal, damaged)
        var refused = blocks[0]
        assert not bindFlatFusion(native, first, refused) and refused == blocks[0],
            "folded source facts cannot evade binding validation"
        var reconstructed = default(FusionSourceBlock)
        assert decodeFusionSource(native.plan, CodeAddress(0), reconstructed) and reconstructed == firstSource
        assert writeMetadata(native.plan.facts, ordinal, original)
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
      var stopped = default(FlatFact)
      assert tryReadFlatFact(native, int(blocks[0].first)+int(blocks[0].span)-1, stopped)
      assert native.info.pc == CodeAddress(uint64(stopped.pc))
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
      # Sample genuine dispatcher entries after all cold/hot and paid-resume controls have finished.
      # The adjacent worker may execute internal peer rounds; those are not dispatcher observations.
      resetFlatFrame(reused, info)
      reused.nativeSession = default(NativeSession)
      reused.remaining = 12
      var probe = FlatFusionProbe(down: 1, seed: 0)
      flatDispatchLoop(reused, first, false, true, probe)
      var observed = 0'u32
      for sample in probe.samples:
        if sample.token == second+1: observed += sample.count
      assert observed == 1, "composition sampler observes the actual adjacent header entry"
