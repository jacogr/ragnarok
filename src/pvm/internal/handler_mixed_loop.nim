# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind a bounded mixed self-loop to exact checked source and cached branch edges.

when declared(FlatFrame):
  proc buildFlatMixedLoop(f: FlatFrame, pc: uint32, epoch: uint64): NativeMixedLoop =
    ## Only an ordinary complete header with the original operands and price can certify a visit.
    result = default(NativeMixedLoop)
    if epoch == 0 or f.plan == nil or f.plan.allowNative or f.plan.singleStep or
        f.pricingKind != 0 or f.preparationFailure != FlatError.None: return
    var header = 0'u32
    var source = default(FlatSourceInterval)
    var walk = default(FlatSourceSummary)
    if not flatCompleteOriginalHeader(f, pc, NativeReadFactLimit, header, source) or
        source.span < NativeMixedLoopMinimum or f.handlers[int(header)] != flatCharge or
        not flatWalkCompleteSource(f, header, source, walk) or
        walk.operations < NativeMixedLoopMinimum or walk.terminal >= NativeEntryLimit or
        f.handlers[int(walk.terminal)] != flatBranch[171]: return
    let price = blockGas(f.plan.source, CodeAddress(uint64(pc)), f.plan.cycles)
    if price.error != GasError.None or uint64(price.value) != source.price: return
    let priceIndex = f.plan.facts[int(source.first)].priceIndex
    var proof = NativeMixedLoop(header: header, first: source.first, terminal: walk.terminal,
      price: source.price, epoch: epoch, span: uint8(source.span), count: uint8(walk.operations))
    var node = header+1
    for ordinal in source.first..source.last:
      let fact = f.plan.facts[int(ordinal)]
      if fact.priceIndex != priceIndex: return
      if fact.opcode == 2: continue # The original price and attempt span still include this fact.
      let original = flatSourcePayload(f.plan, fact)
      let actual = f.arguments[int(node)]
      if actual.slots != original.args.slots: return
      if node == walk.terminal:
        var exitSource = default(FlatSourceInterval)
        let immediateMask = 0xffffffff'u64
        if original.handler != flatUnresolvedBranch[171] or uint32(original.args.x shr 32) != pc or
            uint32(actual.x shr 32) != header or
            (actual.x and immediateMask) != (original.args.x and immediateMask) or
            not flatCompleteOriginalHeader(f, original.args.y, high(uint32), proof.exitHeader,
              exitSource) or actual.y != proof.exitHeader: return
      else:
        if actual.x != original.args.x or actual.y != original.args.y: return
        let worker = f.handlers[int(node)]
        if worker != original.handler:
          let paired = if isRegisterOpcode(fact.opcode): flatRegisterPairHandler(fact.opcode)
            else: flatMemoryPairHandler(fact.opcode)
          if paired == nil or worker != paired: return
      proof.operations[int(node-header-1)] = NativeOperation(opcode: fact.opcode,
        slots: original.args.slots, immediate: (if node ==
            walk.terminal: 0'u64 else: original.args.x))
      inc node
    if proof.complete: result = proof

  proc observeFlatMixedLoop(f: var FlatFrame, pc, header, terminal: uint32) =
    ## Bound exact source reconstruction to cold resolved BNEs with a plausible byte store.
    if terminal <= header or terminal-header < NativeMixedLoopMinimum or
        terminal-header > NativeReadFactLimit: return
    let epoch = nativeEpoch(f.nativeSession)
    if epoch == 0: return
    if f.mixedSource.epoch != epoch: f.mixedSource = FlatMixedLoopSource(epoch: epoch)
    if f.mixedSource.count == uint8(FlatMixedCandidateLimit) or
        f.mixedSource.checks == uint8(FlatMixedCandidateLimit): return
    let token = pc+1
    for index in 0..<int(f.mixedSource.count):
      if f.mixedSource.candidates[index] == token: return
    let first = int(f.sites[int(header)])
    let span = f.arguments[int(header)].y
    if span > NativeReadFactLimit or first+int(span) > f.plan.facts.len: return
    var store = false
    for index in first..<first+int(span):
      if f.plan.facts[index].opcode == 120:
        store = true
        break
    if not store: return
    inc f.mixedSource.checks
    let proof = buildFlatMixedLoop(f, pc, epoch)
    if not proof.complete or proof.header != header or proof.terminal != terminal: return
    f.mixedSource.candidates[int(f.mixedSource.count)] = token
    inc f.mixedSource.count
    when defined(pvmMixedLoopWitness):
      let exitPc = f.plan.facts[int(f.sites[int(proof.exitHeader)])].pc
      echo "MIXED_LOOP_PROOF,", pc, ",", proof.first, ",", exitPc, ",", proof.price,
        ",", proof.epoch, ",", proof.header, ",", proof.terminal
      for index in 0..<int(proof.count):
        let operation = proof.operations[index]
        echo "MIXED_LOOP_OP,", index, ",", operation.opcode, ",", operation.slots.aIndex,
          ",", operation.slots.bIndex, ",", operation.slots.dIndex, ",",
          operation.slots.destinationIndex, ",", operation.immediate

  template enterFlatMixedLoop(f: var FlatFrame, off: uint32, certificate: NativeMixedLoop, image,
      enter: untyped): uint32 =
    ## Each entry borrows fresh descriptors and charges only verified complete visits.
    let boundProof {.cursor.}: NativeMixedLoop = certificate
    assert off == boundProof.header
    if f.info.blockCharged or f.barrier != flatStop: return flatCharge(f, off)
    let gas = uint64(f.info.gas)
    let funded = nativeMixedLoopBudget(boundProof.span, boundProof.price, gas, f.remaining)
    if funded == 0: return flatCharge(f, off)
    var context = NativeMixedLoopContext(read: [initNativeReadRegion(f.stackBase, f.stack),
      flatRWReadRegion(f.rwBase, f.rw), initNativeReadRegion(f.roBase, f.ro)],
      visitLimit: uint64(funded))
    context.writable[0] = NativeCycleWritable(first: f.stackBase, length: uint64(f.stack.len))
    context.writable[1] = NativeCycleWritable(first: f.rwBase, length: uint64(f.rw.len))
    if f.stack.len > 0: context.writable[0].data = addr f.stack[0]
    if f.rw.len > 0: context.writable[1].data = addr f.rw[0]
    if f.dirtyPages.len > 0: context.dirty = addr f.dirtyPages[0]
    context.dirtyWords = uint64(f.dirtyPages.len)
    let raw: uint32 = enter(image[], f.info.registers, context)
    let receipt: NativeMixedLoopReceipt = nativeMixedLoopReceipt(boundProof, funded, raw,
      f.info.registers)
    if not receipt.valid: abortNativeReceipt()
    when defined(pvmMixedLoopWitness) or defined(pvmMixedLoopEntryWitness):
      inc f.mixedWitnessEntries
    if receipt.visits != 0:
      let visits = uint64(receipt.visits)
      f.info.gas = MachineGas(gas-visits*boundProof.price)
      f.remaining -= visits*uint64(boundProof.span)
      f.reservation = off or flatReservationHeaderFlag
      recordNativeMixedLoop(f.nativeSession, visits*uint64(boundProof.span))
      when defined(pvmMixedLoopWitness) or defined(pvmMixedLoopEntryWitness):
        f.mixedWitnessVisits += visits
    if receipt.next == off and receipt.visits < funded:
      # Replay the first unstarted visit once. Returning to the installed entry here would spin.
      when defined(pvmMixedLoopWitness) or defined(pvmMixedLoopEntryWitness):
        inc f.mixedWitnessRefusals
      return flatCharge(f, off)
    receipt.next

  when defined(pvmMixedLoopEntryWitness):
    proc flatMixedLoopEntryWitness(f: var FlatFrame, off: uint32): uint32 =
      let image = f.mixedWitnessImage
      if image == nil: return flatCharge(f, off)
      enterFlatMixedLoop(f, off, f.mixedWitnessProof, image, enterNativeMixedLoop)

  proc flatMixedLoopEntry(f: var FlatFrame, off: uint32): uint32 =
    let image = f.mixedImage
    let proof = f.mixedProof
    if image == nil or proof == nil: return flatCharge(f, off)
    enterFlatMixedLoop(f, off, proof[], image, enterNativeMixedLoop)

  proc borrowFlatMixedLoopSegment(f: var FlatFrame, proof: ptr NativeMixedLoop) =
    ## The second entry changes only its own checked header for the duration of this segment.
    let header = proof[].header
    assert f.mixedImage == nil and f.mixedProof == nil and f.handlers[int(header)] == flatCharge
    let image = borrowNativeMixedLoop(f.nativeSession, proof[])
    if image == nil: return
    f.mixedProof = proof
    f.mixedImage = image
    when defined(pvmMixedLoopWitness) or defined(pvmMixedLoopEntryWitness):
      f.mixedWitnessEntries = 0
      f.mixedWitnessVisits = 0
      f.mixedWitnessRefusals = 0
    f.handlers[int(header)] = flatMixedLoopEntry

  proc returnFlatMixedLoopSegment(f: var FlatFrame) =
    ## Restore the original header and drop both invocation borrows before release.
    let proof = f.mixedProof
    let image = f.mixedImage
    assert proof != nil and image != nil
    let header = proof[].header
    assert f.handlers[int(header)] == flatMixedLoopEntry
    f.handlers[int(header)] = flatCharge
    f.mixedImage = nil
    f.mixedProof = nil
    when defined(pvmMixedLoopWitness):
      echo "MIXED_LOOP_SEGMENT,", f.mixedWitnessEntries, ",", f.mixedWitnessVisits, ",",
        f.mixedWitnessRefusals, ",", image[].codeBytes
    returnNativeMixedLoop(f.nativeSession)

  when defined(pvmSharedAsyncWitness) or defined(pvmMixedLoopEntryWitness):
    proc witnessFlatMixedLoop*(program: Program, pc: uint32, matches: bool) =
      ## Rebuild the same proof from genuine checked emission, then challenge each authority.
      let cycles = GasCycleLimit(100000)
      var prepared = prepareFlatPlan(program, cycles, defaultFlatLimits(), false)
      assert prepared.error == FlatError.None
      let plan = takeValue(prepared)
      let info = MachineInfo(pc: CodeAddress(uint64(pc)), gas: MachineGas(1000000))
      var frame = newFlatFrame(plan, [], info)
      let header = flatResolve(frame, pc)
      assert header != flatStop
      var source = default(FlatSourceInterval)
      var walk = default(FlatSourceSummary)
      assert flatSourceIntervalAt(frame, header, 64, source)
      assert flatWalkCompleteSource(frame, header, source, walk)
      let terminal = walk.terminal
      assert not buildFlatMixedLoop(frame, pc, 1).complete
      assert frame.handlers[int(terminal)] == flatUnresolvedBranch[171]
      assert flatUnresolvedBranch[171](frame, terminal) == terminal
      let proof = buildFlatMixedLoop(frame, pc, 1)
      assert proof.complete == matches
      if not matches: return
      assert proof.header == header and proof.terminal == terminal
      assert proof.exitHeader != header and proof.exitHeader == frame.arguments[int(terminal)].y
      assert not buildFlatMixedLoop(frame, pc, 0).complete
      assert not buildFlatMixedLoop(frame, frame.plan.facts[int(source.first+1)].pc, 1).complete
      assert buildFlatMixedLoop(frame, pc, 2).epoch != proof.epoch
      let price = frame.arguments[int(header)].x
      frame.arguments[int(header)].x = price+1
      assert not buildFlatMixedLoop(frame, pc, 1).complete
      frame.arguments[int(header)].x = price
      let span = frame.arguments[int(header)].y
      frame.arguments[int(header)].y = span-1
      assert not buildFlatMixedLoop(frame, pc, 1).complete
      frame.arguments[int(header)].y = span
      var store = int(header)+1
      while proof.operations[store-int(header)-1].opcode != 120: inc store
      let displacement = frame.arguments[store].x
      frame.arguments[store].x = displacement xor 1
      assert not buildFlatMixedLoop(frame, pc, 1).complete
      frame.arguments[store].x = displacement
      let originalWorker = frame.handlers[store]
      frame.handlers[store] = flatBudget
      assert not buildFlatMixedLoop(frame, pc, 1).complete
      frame.handlers[store] = originalWorker
      let branch = frame.arguments[int(terminal)]
      frame.arguments[int(terminal)].y = header
      assert not buildFlatMixedLoop(frame, pc, 1).complete
      frame.arguments[int(terminal)] = branch
      frame.arguments[int(terminal)].x = uint64(proof.exitHeader) shl 32
      assert not buildFlatMixedLoop(frame, pc, 1).complete
      frame.arguments[int(terminal)] = branch
      assert buildFlatMixedLoop(frame, pc, 1) == proof

      assert nativeMixedLoopBudget(proof.span, proof.price, proof.price, uint64(proof.span)-1) == 0
      assert nativeMixedLoopBudget(proof.span, proof.price, proof.price, uint64(proof.span)) == 1
      assert nativeMixedLoopBudget(proof.span, proof.price, proof.price-1, uint64(proof.span)) == 0
      assert nativeMixedLoopBudget(proof.span, high(uint64), high(uint64), high(uint64)) == 1
      assert nativeMixedLoopBudget(proof.span, 0, 0, high(uint64)) == NativeMixedLoopVisitLimit
      var registers = default(RegisterFile)
      assert nativeMixedLoopReceipt(proof, 2, 0, registers).next == header
      assert not nativeMixedLoopReceipt(proof, 2, NativeMixedLoopExitBit, registers).valid
      assert not nativeMixedLoopReceipt(proof, 2, 3, registers).valid
      assert not nativeMixedLoopReceipt(proof, 2, 1, registers).valid
      let exitReceipt = nativeMixedLoopReceipt(proof, 2, NativeMixedLoopExitBit or 2, registers)
      assert exitReceipt.valid and exitReceipt.visits == 2 and exitReceipt.next == proof.exitHeader
      registers[proof.operations[int(proof.count)-1].slots.aIndex] = RegisterValue(1)
      let repeatReceipt = nativeMixedLoopReceipt(proof, 2, 1, registers)
      assert repeatReceipt.valid and repeatReceipt.visits == 1 and repeatReceipt.next == header
      assert not nativeMixedLoopReceipt(proof, 2, NativeMixedLoopExitBit or 1, registers).valid
