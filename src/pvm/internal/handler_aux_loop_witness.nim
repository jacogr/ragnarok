# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Test-only included witnesses compare the auxiliary path with original checked workers.

when declared(FlatFrame) and defined(pvmAuxLoopWitness):
  proc runAuxCheckedWitness(f: var FlatFrame, header, outside: uint32, visits: uint64) =
    ## Dispatch the original reservation and workers, stopping before the next header.
    var offset = header
    var left = visits
    while offset != flatStop and offset != outside:
      if offset == header:
        if left == 0: return
        dec left
      let selected = f.handlers[int(offset)]
      offset = selected(f, offset)

  proc checkAuxState(f, expected: FlatFrame) =
    assert f.info.pc == expected.info.pc and f.info.gas == expected.info.gas
    assert f.info.registers == expected.info.registers
    assert f.info.blockCharged == expected.info.blockCharged
    assert f.remaining == expected.remaining and f.reservation == expected.reservation
    assert f.reason == expected.reason and f.exit == expected.exit
    assert f.attemptedExit == expected.attemptedExit and f.stoppedAt == expected.stoppedAt
    assert f.barrier == expected.barrier and f.barrierFact == expected.barrierFact
    assert f.dirtyPages == expected.dirtyPages and f.dirtyIndices == expected.dirtyIndices
    assert f.rw.len == expected.rw.len
    for at in 0..<f.rw.len: assert f.rw[at] == expected.rw[at]

  proc witnessAuxRefusals*(program: Program) =
    ## Independent checked worker receipts before and after fallback for each refusal.
    var prepared = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
    assert prepared.error == FlatError.None
    let plan = takeValue(prepared)
    const writeAddress = 0x13000'u64
    const readAddress = 0x11000'u64
    var writable = PageImage(index: PageIndex(uint32(writeAddress shr 12)),
      access: PageAccess.ReadWrite, bytes: default(array[4096, byte]))
    writable.bytes[0] = 0xff
    var readable = PageImage(index: PageIndex(uint32(readAddress shr 12)),
      access: PageAccess.ReadOnly, bytes: default(array[4096, byte]))
    readable.bytes[0] = 0x24
    var firstRead = PageImage(index: PageIndex(0x10), access: PageAccess.ReadOnly,
      bytes: default(array[4096, byte]))
    firstRead.bytes[0] = 0x35
    let price = blockGas(program, CodeAddress(0), GasCycleLimit(100000))
    assert price.error == GasError.None and uint64(price.value) > 0
    let cleanNext = PageImage(index: PageIndex(uint32(writeAddress shr 12)+1),
      access: PageAccess.ReadWrite, bytes: default(array[4096, byte]))
    for scenario in 0..17:
      var incoming = MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000),
        registers: default(RegisterFile), blockCharged: false)
      incoming.registers[5] = RegisterValue(case scenario
        of 6: readAddress
        of 12, 13, 16: writeAddress+4095
        else: writeAddress)
      incoming.registers[6] = RegisterValue(if scenario == 11: readAddress+4095 else: readAddress)
      if scenario == 12 or scenario == 13 or scenario == 16: incoming.registers[7] = RegisterValue(1)
      if scenario == 0: incoming.blockCharged = true
      if scenario == 3: incoming.gas = MachineGas(uint64(price.value)-1)
      if scenario == 9: incoming.registers[12] = RegisterValue(8)
      if scenario == 10: incoming.gas = MachineGas(uint64(price.value))
      let pages = case scenario
        of 4: @[firstRead, writable]
        of 13, 16: @[firstRead, readable, writable, cleanNext]
        else: @[firstRead, readable, writable]
      var actual = newFlatFrame(plan, pages, incoming)
      var expected = newFlatFrame(plan, pages, incoming)
      let header = flatResolve(actual, 0)
      let expectedHeader = flatResolve(expected, 0)
      assert header != flatStop and header == expectedHeader
      let terminal = header+15
      # Bind both arms with the original preparatory worker, then restore input paid state.
      discard flatUnresolvedBranch[171](actual, terminal)
      discard flatUnresolvedBranch[171](expected, terminal)
      actual.info = incoming
      expected.info = incoming
      actual.barrier = flatStop
      expected.barrier = flatStop
      actual.remaining = case scenario
        of 1: 0'u64
        of 2: 14'u64
        of 8, 15: 16'u64
        of 17: 31'u64
        else: 30'u64
      expected.remaining = actual.remaining
      if scenario != 5:
        flatMarkStore[1](actual, writeAddress)
        flatMarkStore[1](expected, writeAddress)
      if scenario == 7:
        # Break list membership alone, then restore the original invariant before fallback.
        actual.dirtyIndices.setLen(0)
        expected.dirtyIndices.setLen(0)
      if scenario == 14:
        # Independently refuse a stale list entry when the bitmap is clear.
        let word = int(writeAddress shr 18)
        let bit = 1'u64 shl int((writeAddress shr 12) and 63)
        actual.dirtyPages[word] = actual.dirtyPages[word] and not bit
        expected.dirtyPages[word] = expected.dirtyPages[word] and not bit
      if scenario == 16:
        # Mark the second page only in the bitmap, forcing a scan after the address changes.
        let page = uint32((writeAddress shr 12)+1)
        let word = int(page shr 6)
        let bit = 1'u64 shl int(page and 63)
        actual.dirtyPages[word] = actual.dirtyPages[word] or bit
        expected.dirtyPages[word] = expected.dirtyPages[word] or bit
      var proof = AuxProof(read: initNativeAuxReadPrefix(header, 0, 1),
        price: uint64(price.value), exitHeader: actual.arguments[int(terminal)].y)
      for i in 0..<15:
        let fact = actual.plan.facts[i]
        let args = flatSourcePayload(actual.plan, fact).args
        let op = NativeOperation(opcode: fact.opcode, slots: args.slots, immediate: args.x)
        if i < 11:
          assert addReadBodyOperation(proof.read, header+1+uint32(i), uint32(i), op)
        elif i == 11: proof.store = op
        elif i < 14: proof.suffix[i-12] = op
        else: proof.branch = args.slots
      var image = lowerNativeReadBody(proof.read)
      assert image.ready
      let budget = actual.remaining
      var reason = AuxRefusal.None
      let next = runFlatAuxChunk(actual, proof, image, reason)
      let committed = (budget-actual.remaining) div AuxVisitSpan
      assert budget-actual.remaining == committed*AuxVisitSpan
      let wanted = [AuxRefusal.Paid, AuxRefusal.Budget, AuxRefusal.Budget,
        AuxRefusal.Gas, AuxRefusal.Read, AuxRefusal.Dirty, AuxRefusal.Writable,
        AuxRefusal.Dirty, AuxRefusal.Budget, AuxRefusal.None, AuxRefusal.Gas,
        AuxRefusal.Read, AuxRefusal.Writable, AuxRefusal.Dirty, AuxRefusal.Dirty,
        AuxRefusal.Budget, AuxRefusal.Dirty, AuxRefusal.Budget]
      assert reason == wanted[scenario], "refusal reason"
      let wantedVisits = case scenario
        of 8..13, 15, 16: 1'u64
        of 17: 2'u64
        else: 0'u64
      assert committed == wantedVisits
      if wantedVisits != 0:
        runAuxCheckedWitness(expected, header, proof.exitHeader, wantedVisits)
      checkAuxState(actual, expected)
      if scenario == 9:
        assert next == proof.exitHeader
      else:
        assert next == header
        if scenario == 7:
          actual.dirtyIndices.add(uint32(writeAddress shr 12))
          expected.dirtyIndices.add(uint32(writeAddress shr 12))
        if scenario == 14:
          actual.dirtyIndices.setLen(0)
          expected.dirtyIndices.setLen(0)
        if scenario == 15:
          # The previous borrow saw this page. A fresh borrow must prove it again.
          actual.remaining = 15
          expected.remaining = 15
          actual.dirtyIndices.setLen(0)
          expected.dirtyIndices.setLen(0)
          let again = runFlatAuxChunk(actual, proof, image, reason)
          assert again == header and actual.remaining == 15 and reason == AuxRefusal.Dirty
          checkAuxState(actual, expected)
          actual.dirtyIndices.add(uint32(writeAddress shr 12))
          expected.dirtyIndices.add(uint32(writeAddress shr 12))
        if scenario == 16:
          let page = uint32((writeAddress shr 12)+1)
          actual.dirtyIndices.add(page)
          expected.dirtyIndices.add(page)
        runAuxCheckedWitness(actual, next, proof.exitHeader, 1)
        runAuxCheckedWitness(expected, header, proof.exitHeader, 1)
        checkAuxState(actual, expected)
      image = default(NativeImage)

  proc witnessAuxSourcePattern*(program: Program, pc: uint32, checks: uint8,
      matches, aliases: bool, oneVisit: bool = false) =
    ## Exercise genuine cold resolution, exclusive transfer, and native/checked execution.
    var prepared = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
    assert prepared.error == FlatError.None
    let plan = takeValue(prepared)
    const writeAddress = 0x11000'u64
    const readAddress = 0x10000'u64
    var writable = PageImage(index: PageIndex(uint32(writeAddress shr 12)),
      access: PageAccess.ReadWrite, bytes: default(array[4096, byte]))
    for i in 0..<4: writable.bytes[i] = 0xff
    var readable = PageImage(index: PageIndex(uint32(readAddress shr 12)),
      access: PageAccess.ReadOnly, bytes: default(array[4096, byte]))
    readable.bytes[0] = 0x24
    let pages = [readable, writable]
    var incoming = MachineInfo(pc: CodeAddress(uint64(pc)), gas: MachineGas(1000000),
      registers: default(RegisterFile), blockCharged: false)
    incoming.registers[0] = RegisterValue(0x35)
    incoming.registers[5] = RegisterValue(writeAddress)
    incoming.registers[6] = RegisterValue(readAddress)
    incoming.registers[7] = RegisterValue(1)
    incoming.registers[12] = RegisterValue(if oneVisit: 1 else: 3)
    let runtime = newNativeRuntime()
    try:
      assert start(runtime)
    except:
      assert false, "native compiler thread startup failed"
    let session = newNativeSession(runtime)
    var first = newFlatFrame(plan, pages, incoming)
    first.nativeSession = session
    beginNativeInvocation(session, NativeInvocationFloor)
    runFlat(first, NativeInvocationFloor)
    assert first.exit == oracle.StepExit.Panic and first.reason == oracle.StepError.None
    if oneVisit:
      # The ninth loop ran through to the final trap even after exhausting discovery.
      assert int(first.sites[int(first.stoppedAt)]) == first.plan.facts.len-1
    finishNativeInvocation(session, 0)
    assert flatAuxSourceCurrent(first) == matches and first.auxSource.coldChecks == checks
    assert runtimeInfo(runtime).registered == 0
    if matches:
      assert first.auxSource.pc == pc
      let header = first.auxSource.headerToken-1
      var kept = takeFlatStream(first)
      assert not flatAuxSourceCurrent(first)
      var foreignPrepared = prepareFlatPlan(program, GasCycleLimit(100000),
        defaultFlatLimits(), false)
      assert foreignPrepared.error == FlatError.None
      var foreign = newFlatFrame(takeValue(foreignPrepared), pages, incoming)
      foreign.nativeSession = session
      restoreFlatStream(foreign, kept)
      assert foreign.preparationFailure == FlatError.InvalidProgram
      assert not flatAuxSourceCurrent(foreign)

      var actual = newFlatFrame(plan, pages, incoming)
      actual.nativeSession = session
      restoreFlatStream(actual, kept)
      assert flatAuxSourceCurrent(actual) and kept.auxSource.headerToken == 0
      let proof = buildFlatAuxProof(actual, pc)
      assert proof.read.complete and proof.read.info.header == header

      # Live stream records must independently match the immutable source.
      let originalPrice = actual.arguments[int(header)].x
      actual.arguments[int(header)].x = originalPrice+1
      assert not buildFlatAuxProof(actual, pc).read.complete
      actual.arguments[int(header)].x = originalPrice
      let store = int(header)+12
      let originalStore = actual.arguments[store].x
      actual.arguments[store].x = originalStore xor 1
      assert not buildFlatAuxProof(actual, pc).read.complete
      actual.arguments[store].x = originalStore
      let originalWorker = actual.handlers[store]
      actual.handlers[store] = flatBudget
      assert not buildFlatAuxProof(actual, pc).read.complete
      actual.handlers[store] = originalWorker
      let terminal = int(header)+15
      let originalExit = actual.arguments[terminal].y
      actual.arguments[terminal].y = header
      assert not buildFlatAuxProof(actual, pc).read.complete
      actual.arguments[terminal].y = originalExit

      # Execute exactly three original visits with an already-dirty page.
      var expected = newFlatFrame(plan, pages, incoming)
      let checkedHeader = flatResolve(expected, pc)
      assert checkedHeader == header
      discard flatUnresolvedBranch[171](expected, checkedHeader+15)
      expected.info = incoming
      actual.remaining = 47
      expected.remaining = 47
      actual.barrier = flatStop
      expected.barrier = flatStop
      flatMarkStore[1](actual, writeAddress)
      flatMarkStore[1](expected, writeAddress)
      var image = lowerNativeReadBody(proof.read)
      assert image.ready
      var refusal = AuxRefusal.None
      let next = runFlatAuxChunk(actual, proof, image, refusal)
      assert next == proof.exitHeader and actual.remaining == 2
      assert refusal == AuxRefusal.None
      runAuxCheckedWitness(expected, checkedHeader, proof.exitHeader, 3)
      checkAuxState(actual, expected)
      if aliases:
        assert actual.rw[0] == 0xff and actual.rw[1] == 1 and actual.rw[3] == 3
      else:
        assert actual.rw[0] == 0x35 and actual.rw[2] == 0x35 and actual.rw[3] == 0xff
      image = default(NativeImage)
      invalidateNativeStream(session)
      assert not flatAuxSourceCurrent(actual)
    assert close(runtime)
