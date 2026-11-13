# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind a complete original self-loop to its cached edges, decoded operands and block price.
## A transactional visit has a guarded read prefix, byte Store and infallible suffix;
## a paid visit can preserve either of two ordered read/store groups before a later guard
## resumes checked execution. Both address forms and all four store widths use that receipt.
## Folded no-ops still count toward gas and the original attempt span. Cold branch
## resolution retains at most eight accepted candidates from sixteen bounded source
## reconstructions per stream epoch. The frame ranks their checked visits beside a ready Read owner.

when declared(FlatFrame):
  proc buildFlatMixedLoop(f: FlatFrame, pc: uint32, epoch: uint64,
      allowPaid = true): NativeMixedLoop =
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
          if paired == nil or worker != paired:
            # A fused pair must name both adjacent original scalar facts. The ordered source walk
            # and the next iteration independently bind the second site's worker and operands.
            if ordinal >= source.last or node+1 >= walk.terminal or
                f.sites[int(node+1)] != ordinal+1: return
            let nextFact = f.plan.facts[int(ordinal+1)]
            let fused = flatFusedRegisterHandler(fact.opcode, nextFact.opcode)
            if fused == nil or worker != fused or nextFact.priceIndex != priceIndex: return
      proof.operations[int(node-header-1)] = NativeOperation(opcode: fact.opcode,
        slots: original.args.slots, immediate: (if node ==
            walk.terminal: 0'u64 else: original.args.x))
      inc node
    if allowPaid: proof.paidGuards = nativeMixedLoopPaidGuards(proof)
    if not proof.complete: return
    # Reprice only a route that can actually become a certificate.
    let price = blockGas(f.plan.source, CodeAddress(uint64(pc)), f.plan.cycles)
    if price.error == GasError.None and uint64(price.value) == source.price: result = proof

  proc observeFlatMixedLoop(f: var FlatFrame, pc, header, terminal: uint32) =
    ## Bound exact source reconstruction to cold resolved BNEs with a plausible scalar store.
    ## Refused early loops consume reconstruction work without occupying the accepted
    ## inventory. A separate ceiling permits later useful loops after those refusals:
    ## at most sixteen cold attempts, each spanning at most NativeReadFactLimit facts,
    ## per stream epoch. Revalidation of retained certificates is a separate segment step.
    if terminal <= header or terminal-header < NativeMixedLoopMinimum or
        terminal-header > NativeReadFactLimit: return
    let epoch = nativeEpoch(f.nativeSession)
    if epoch == 0: return
    if f.mixedSource.epoch != epoch: f.mixedSource = FlatMixedLoopSource(epoch: epoch)
    if f.mixedSource.count == uint8(NativeMixedLoopCandidateLimit) or
        f.mixedSource.checks == uint8(NativeMixedLoopReconstructionLimit): return
    let token = pc+1
    for index in 0..<int(f.mixedSource.count):
      if f.mixedSource.candidates[index] == token: return
    let first = int(f.sites[int(header)])
    let span = f.arguments[int(header)].y
    if span > NativeReadFactLimit or first+int(span) > f.plan.facts.len: return
    var store = false
    for index in first..<first+int(span):
      if nativeMixedLoopStoreWidth(f.plan.facts[index].opcode) != 0:
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

  when defined(pvmPaidMixedLoopWitness):
    proc observeFlatMixedPair(f: var FlatFrame, header: uint32, receipt: NativeMixedLoopReceipt,
        funded: uint32, operations: uint64) =
      let pair = f.mixedPair
      if pair == nil: return
      for index in 0..1:
        if pair[].images[index] == nil or pair[].proofs[index].header != header: continue
        template counters: untyped = pair[].counts[index]
        inc counters.entries
        counters.visits += uint64(receipt.visits)
        counters.operations += operations
        if receipt.visits != 0: inc counters.branches
        if receipt.visits > 1: inc counters.repeatedHeaders
        if receipt.paid:
          inc counters.paid
          let ordinal = f.sites[int(receipt.next)]
          counters.lastGuardOrdinal = ordinal
          counters.lastGuardPc = f.plan.facts[int(ordinal)].pc
        if receipt.paid or (receipt.next == header and receipt.visits < funded):
          inc counters.refusals
        break

  when defined(pvmMixedLoopWitness):
    proc observeFlatMixedArena(f: var FlatFrame, off: uint32, receipt: NativeMixedLoopReceipt,
        funded: uint32, operations: uint64) =
      let requested = f.mixedProofs
      if requested == nil: return
      for index in 0..<int(requested[].count):
        if requested[].proofs[index].header != off: continue
        template counters: untyped = f.mixedArenaWitness[index]
        inc counters.entries
        counters.visits += uint64(receipt.visits)
        counters.operations += operations
        if receipt.visits != 0: inc counters.branches
        if receipt.visits > 1: inc counters.repeatedHeaders
        if receipt.paid: inc counters.paid
        if receipt.paid or (receipt.next == off and receipt.visits < funded): inc counters.refusals
        break

  template enterFlatMixedLoop(f: var FlatFrame, off: uint32, certificate: NativeMixedLoop, image,
      enter: untyped): uint32 =
    ## Borrow fresh read, writable and dirty-page descriptors for at most 256 funded visits.
    ## Entry requires an unpaid header and no quota barrier; otherwise use flatCharge.
    ## Whole visits consume their original span and price. An unpaid refusal replays
    ## its unstarted header once through checked charging. A packed paid guard keeps
    ## the committed prefix live: charge visits+1 blocks, subtract visits+1 complete
    ## spans from remaining, mark blockCharged, and retain the original header reservation.
    ## Return the source-certified guard node directly so checked workers consume the
    ## reserved suffix. The caller's reservation/refund path accounts for unused attempts
    ## on a fault or stop; it must never charge this already paid block again.
    ## Credited native work is whole visits plus the original prefix, including folded
    ## no-ops; a prefix without a completed BNE credits work/calls but no branch/header.
    let boundProof {.cursor.}: NativeMixedLoop = certificate
    if off != boundProof.header: return flatLocal(f, off, oracle.StepError.BackendFailure)
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
    if not receipt.valid: return flatLocal(f, off, oracle.StepError.BackendFailure)
    when defined(pvmMixedLoopWitness) or defined(pvmMixedLoopEntryWitness):
      inc f.mixedWitnessEntries
    if receipt.paid:
      if receipt.next <= off or receipt.next >= boundProof.terminal or
          uint64(receipt.next) >= uint64(f.sites.len):
        return flatLocal(f, off, oracle.StepError.BackendFailure)
      let ordinal = f.sites[int(receipt.next)]
      if ordinal < boundProof.first or ordinal-boundProof.first >= uint32(boundProof.span):
        return flatLocal(f, off, oracle.StepError.BackendFailure)
      let visits = uint64(receipt.visits)
      let reserved = visits+1
      let prefix = uint64(ordinal-boundProof.first)
      let operations = visits*uint64(boundProof.span)+prefix
      f.info.gas = MachineGas(gas-reserved*boundProof.price)
      f.info.blockCharged = true
      f.remaining -= reserved*uint64(boundProof.span)
      f.reservation = off or flatReservationHeaderFlag
      if operations != 0: recordNativeMixedLoop(f.nativeSession, operations, visits > 1, visits != 0)
      when defined(pvmPaidMixedLoopWitness):
        observeFlatMixedPair(f, off, receipt, funded, operations)
      when defined(pvmMixedLoopWitness):
        observeFlatMixedArena(f, off, receipt, funded, operations)
      when defined(pvmMixedLoopWitness) or defined(pvmMixedLoopEntryWitness):
        f.mixedWitnessVisits += visits
        inc f.mixedWitnessRefusals
      return receipt.next
    when defined(pvmPaidMixedLoopWitness):
      observeFlatMixedPair(f, off, receipt, funded, uint64(receipt.visits)*uint64(boundProof.span))
    when defined(pvmMixedLoopWitness):
      observeFlatMixedArena(f, off, receipt, funded, uint64(receipt.visits)*uint64(boundProof.span))
    if receipt.visits != 0:
      let visits = uint64(receipt.visits)
      f.info.gas = MachineGas(gas-visits*boundProof.price)
      f.remaining -= visits*uint64(boundProof.span)
      f.reservation = off or flatReservationHeaderFlag
      recordNativeMixedLoop(f.nativeSession, visits*uint64(boundProof.span), visits > 1)
      when defined(pvmMixedLoopWitness) or defined(pvmMixedLoopEntryWitness):
        f.mixedWitnessVisits += visits
    if receipt.next == off and receipt.visits < funded:
      # Replay the first unstarted visit once. Returning to the installed entry here would spin.
      when defined(pvmMixedLoopWitness) or defined(pvmMixedLoopEntryWitness):
        inc f.mixedWitnessRefusals
      return flatCharge(f, off)
    receipt.next

  when defined(pvmPaidMixedLoopWitness):
    proc flatMixedPairEntry(f: var FlatFrame, off: uint32): uint32 =
      let pair = f.mixedPair
      assert pair != nil
      for index in 0..1:
        let image = pair[].images[index]
        if image != nil and pair[].proofs[index].header == off:
          return enterFlatMixedLoop(f, off, pair[].proofs[index], image, enterNativeMixedLoop)
      flatCharge(f, off)

  when defined(pvmMixedLoopEntryWitness):
    proc flatMixedLoopEntryWitness(f: var FlatFrame, off: uint32): uint32 =
      let image = f.mixedWitnessImage
      if image == nil: return flatCharge(f, off)
      enterFlatMixedLoop(f, off, f.mixedWitnessProof, image, enterNativeMixedLoop)

  proc flatMixedLoopEntry(f: var FlatFrame, off: uint32): uint32 =
    let image = f.mixedImage
    let requested = f.mixedProofs
    if image == nil or requested == nil: return flatCharge(f, off)
    for index in 0..<int(requested[].count):
      if (f.mixedMask and (1'u8 shl index)) != 0 and requested[].proofs[index].header == off:
        template selected(entry, registers, context: untyped): untyped =
          enterNativeMixedLoopAt(entry, uint8(index), registers, context)
        return enterFlatMixedLoop(f, off, requested[].proofs[index], image, selected)
    flatLocal(f, off, oracle.StepError.BackendFailure)

  proc borrowFlatMixedLoopSegment(f: var FlatFrame,
      requested: ptr NativeMixedLoopSet): NativeMixedLoopBorrow =
    ## Borrow the arena once, and patch only the proof slots the immutable image actually published.
    assert f.mixedImage == nil and f.mixedProofs == nil and f.mixedMask == 0
    result = borrowNativeMixedLoops(f.nativeSession, requested[])
    if result.image == nil: return
    f.mixedProofs = requested
    f.mixedImage = result.image
    f.mixedMask = result.mask
    when defined(pvmMixedLoopWitness):
      f.mixedArenaWitness = default(array[NativeMixedLoopEntryLimit, FlatMixedArenaWitness])
    when defined(pvmMixedLoopWitness) or defined(pvmMixedLoopEntryWitness):
      f.mixedWitnessEntries = 0
      f.mixedWitnessVisits = 0
      f.mixedWitnessRefusals = 0
    for index in 0..<int(requested[].count):
      if (result.mask and (1'u8 shl index)) == 0: continue
      let header = requested[].proofs[index].header
      assert f.handlers[int(header)] == flatCharge
      f.handlers[int(header)] = flatMixedLoopEntry

  proc returnFlatMixedLoopSegment(f: var FlatFrame) =
    ## Restore every original checked header before dropping either borrow or releasing the arena.
    let requested = f.mixedProofs
    let image = f.mixedImage
    assert requested != nil and image != nil
    for index in 0..<int(requested[].count):
      if (f.mixedMask and (1'u8 shl index)) == 0: continue
      let header = requested[].proofs[index].header
      restoreFlatTemporaryHandler(f, header, flatMixedLoopEntry, flatCharge)
    when defined(pvmMixedLoopWitness):
      for index in 0..<int(requested[].count):
        if (f.mixedMask and (1'u8 shl index)) == 0: continue
        let proof {.cursor.} = requested[].proofs[index]
        let counts = f.mixedArenaWitness[index]
        let geometry = witnessNativeMixedLoopGeometry(image[], uint8(index))
        let pc = f.plan.facts[int(f.sites[int(proof.header)])].pc
        echo "MIXED_ARENA_ENTRY,", pc, ",", index, ",", counts.entries, ",", counts.visits,
          ",", counts.refusals, ",", counts.paid, ",", counts.operations, ",", counts.branches,
          ",", counts.repeatedHeaders, ",", image[].codeBytes, ",", f.mixedMask,
          ",", geometry.offset, ",", geometry.length
    f.mixedImage = nil
    f.mixedProofs = nil
    f.mixedMask = 0
    when defined(pvmMixedLoopWitness):
      echo "MIXED_LOOP_SEGMENT,", f.mixedWitnessEntries, ",", f.mixedWitnessVisits, ",",
        f.mixedWitnessRefusals, ",", image[].codeBytes
    returnNativeMixedLoop(f.nativeSession)

  when defined(pvmSharedAsyncWitness) or defined(pvmMixedLoopEntryWitness):
    proc witnessFlatMixedDiscovery*(program: Program, checks, accepted: int,
        lastAccepted: bool) =
      ## Resolve genuine checked branches to exercise both independent discovery ceilings.
      var prepared = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
      assert prepared.error == FlatError.None
      let plan = takeValue(prepared)
      let runtime = newNativeRuntime()
      var frame = newFlatFrame(plan, [], MachineInfo(gas: MachineGas(1000000)))
      frame.nativeSession = newNativeSession(runtime)
      var lastPc = 0'u32
      let extent = codeLength(program)
      assert extent.error == ProgramError.None
      var pc = 0'u64
      while pc < extent.value:
        # Enumerate immutable source; derived facts do not exist before each frame resolves a block.
        let decoded = instruction(program, CodeAddress(pc))
        assert decoded.error == ProgramError.None
        let item = decoded.value
        pc += 1+uint64(item.skip)
        if item.opcode != 171: continue
        let original = flatSourcePayload(decoded)
        lastPc = uint32(original.args.x shr 32)
        let header = flatResolve(frame, lastPc)
        assert header != flatStop
        var source = default(FlatSourceInterval)
        var walk = default(FlatSourceSummary)
        assert flatSourceIntervalAt(frame, header, NativeReadFactLimit, source)
        assert flatWalkCompleteSource(frame, header, source, walk)
        assert frame.handlers[int(walk.terminal)] == flatUnresolvedBranch[171]
        assert flatUnresolvedBranch[171](frame, walk.terminal) == walk.terminal
      assert int(frame.mixedSource.checks) == checks and int(frame.mixedSource.count) == accepted
      var foundLast = false
      for index in 0..<int(frame.mixedSource.count):
        if frame.mixedSource.candidates[index] == lastPc+1: foundLast = true
      assert foundLast == lastAccepted
      assert runtimeInfo(runtime).registered == 0 and close(runtime)

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

      for node in int(header)+1..<int(terminal)-1:
        let ordinal = frame.sites[node]
        let fact = frame.plan.facts[int(ordinal)]
        if ordinal >= source.last: continue
        let next = frame.plan.facts[int(ordinal+1)]
        let fused = flatFusedRegisterHandler(fact.opcode, next.opcode)
        if fused == nil or frame.handlers[node] != fused: continue
        let firstArgs = frame.arguments[node]
        frame.arguments[node].x = firstArgs.x xor 1
        assert not buildFlatMixedLoop(frame, pc, 1).complete
        frame.arguments[node] = firstArgs
        let secondArgs = frame.arguments[node+1]
        frame.arguments[node+1].x = secondArgs.x xor 1
        assert not buildFlatMixedLoop(frame, pc, 1).complete
        frame.arguments[node+1] = secondArgs
        let secondSite = frame.sites[node+1]
        frame.sites[node+1] = secondSite+1
        assert not buildFlatMixedLoop(frame, pc, 1).complete
        frame.sites[node+1] = secondSite
        let wrongPair = if fact.opcode == 151:
            flatFusedRegisterHandler(200, 139) else: flatFusedRegisterHandler(151, 152)
        assert wrongPair != nil
        frame.handlers[node] = wrongPair
        assert not buildFlatMixedLoop(frame, pc, 1).complete
        frame.handlers[node] = fused
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
