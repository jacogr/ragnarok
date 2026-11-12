# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Count completed checked blocks under one exact RegisterRing key. Heat lives
## only in the current public invocation and uses its original step budget.
## The observer counts seven connected Read roles separately from the outside
## successor and self-loops. After actual Ring execution and a successful Halt,
## the final live frame rebuilds the ranked proofs and offers one immutable job.
##
## Each callback-free segment binds the exact ordered proofs before borrowing.
## The frame records every occupied slot's original handler in a bounded ledger.
## It restores the ledger, including quota barrier saves, before returning the
## lease. Source-plan and invocation memory borrows end at the same boundary.

when declared(FlatFrame):
  proc clearFlatAuxiliaryInvocation*(f: var FlatFrame) =
    ## Never carry attempts or a pending reservation into a later public call.
    f.auxiliaryHeat = default(FlatAuxiliaryHeat)

  proc buildFlatAuxiliaryCycle(f: FlatFrame, token: uint32, epoch: uint64): NativeReadCycle =
    ## Rebind the same complete checked graph in the live source stream.
    result = default(NativeReadCycle)
    if token == 0: return
    var read = buildFlatReadBody(f, token-1, epoch)
    if extendFlatReadBody(f, read):
      result = buildFlatReadCycle(f, read)

  proc addFlatAuxiliarySite(f: var FlatFrame, header: uint32,
      kind: FlatAuxiliarySiteKind, role, span: uint8) =
    ## The observation inventory is independent of the executable patch limit.
    for index in 0..<int(f.auxiliaryHeat.count):
      if f.auxiliaryHeat.sites[index].header != header: continue
      # An outside successor may also be a loop. Use its existing loop observation only.
      if f.auxiliaryHeat.sites[index].kind == FlatAuxiliarySiteKind.Outside and
          kind == FlatAuxiliarySiteKind.Loop:
        f.auxiliaryHeat.sites[index].kind = kind
        f.auxiliaryHeat.sites[index].role = role
      return
    let index = int(f.auxiliaryHeat.count)
    if index >= NativeAuxiliaryObservationLimit:
      f.auxiliaryHeat.valid = false
      return
    f.auxiliaryHeat.sites[index] = FlatAuxiliarySite(header: header, kind: kind,
      role: role, span: span)
    inc f.auxiliaryHeat.count

  proc observeFlatAuxiliaryLoop(f: var FlatFrame, proof: NativeMixedLoop, candidate: uint8) =
    if proof.complete and mixedLoopDisjoint(f.nativeSession, proof):
      addFlatAuxiliarySite(f, proof.header, FlatAuxiliarySiteKind.Loop, candidate, proof.span)

  proc observeFlatAuxiliaryCycle(f: var FlatFrame, cycle: NativeReadCycle) =
    for role in NativeCycleRole:
      addFlatAuxiliarySite(f, cycle.layout.sites[role].header,
        FlatAuxiliarySiteKind.CycleRole, uint8(ord(role)), uint8(NativeCycleSpans[role]))
    let outside = cycle.layout.outsideHeader
    let span = f.arguments[int(outside)].y
    if span > 0 and span <= uint32(high(uint8)):
      addFlatAuxiliarySite(f, outside, FlatAuxiliarySiteKind.Outside, 0, uint8(span))

  proc resetFlatRingAuxiliarySource(f: var FlatFrame, key: NativeImageKey) =
    ## Release the Ring-only inventory and refusal history on exact authority change.
    ## Keep decoded self-loop candidates and their original reconstruction budget.
    f.mixedSource.chosenPrimary = key
    f.mixedSource.chosenCount = 0
    f.mixedSource.chosenCycle = 0
    f.mixedSource.refused = 0
    f.mixedSource.cycleToken = 0
    f.mixedSource.cycleScout = 0
    f.mixedSource.cycleLinks = 0
    f.mixedSource.cycleTriedLinks = 0
    f.mixedSource.cycleTriedNodes = 0
    f.mixedSource.cycleChecks = 0
    f.mixedSource.cycleRefused = false

  proc bindFlatAuxiliaryHeat(f: var FlatFrame, key: NativeImageKey) =
    ## Keep at most fifteen observation sites under one exact Ring key and public budget.
    ## A key change discards the previous observations. Only source tokens can survive return.
    let budget = f.auxiliaryHeat.budget
    f.auxiliaryHeat = FlatAuxiliaryHeat(primary: key, budget: budget)
    if budget < NativeInvocationFloor or f.pricingKind != 0 or
        not matchesNativeImage(f.nativeSession, key, NativeKind.RegisterRing): return
    if f.mixedSource.epoch != key.epoch:
      f.mixedSource = FlatMixedLoopSource(epoch: key.epoch)
    if f.mixedSource.chosenPrimary != key:
      resetFlatRingAuxiliarySource(f, key)
    if f.mixedSource.chosenCount != 0: return
    f.auxiliaryHeat.valid = true
    for index in 0..<int(f.mixedSource.count):
      if (f.mixedSource.refused and (1'u8 shl index)) == 0:
        let proof = buildFlatMixedLoop(f, f.mixedSource.candidates[index]-1, key.epoch)
        observeFlatAuxiliaryLoop(f, proof, uint8(index))
    if f.mixedSource.cycleToken != 0 and not f.mixedSource.cycleRefused:
      let cycle = buildFlatAuxiliaryCycle(f, f.mixedSource.cycleToken, key.epoch)
      if cycle.read.complete and not nativeReadCycleObservationOverlaps(f.nativeSession, cycle):
        observeFlatAuxiliaryCycle(f, cycle)

  proc beginFlatAuxiliaryInvocation*(f: var FlatFrame, budget: uint64) =
    clearFlatAuxiliaryInvocation(f)
    f.auxiliaryHeat.budget = budget
    let key = nativeInstalledKey(f.nativeSession)
    if key.ticket != 0 and key.kind == NativeKind.RegisterRing:
      bindFlatAuxiliaryHeat(f, key)
    elif f.mixedSource.chosenPrimary.kind == NativeKind.RegisterRing:
      resetFlatRingAuxiliarySource(f, key)

  proc creditFlatAuxiliaryBlock(f: var FlatFrame, index: int, visits: uint64) =
    ## The public quota bounds all exact counts, including observations excluded from ranking.
    let attempts = visits*uint64(f.auxiliaryHeat.sites[index].span)
    if attempts == 0 or attempts > f.auxiliaryHeat.budget-f.auxiliaryHeat.total:
      f.auxiliaryHeat.valid = false
      return
    f.auxiliaryHeat.total += attempts
    f.auxiliaryHeat.sites[index].attempts += attempts
    f.auxiliaryHeat.sites[index].visits += visits

  proc settleFlatAuxiliaryBlock(f: var FlatFrame) =
    let pending = f.auxiliaryHeat.pending
    if pending == 0: return
    f.auxiliaryHeat.pending = 0
    let index = int(pending)-1
    if not f.info.blockCharged and f.reason == oracle.StepError.None and
        f.reservation == (f.auxiliaryHeat.sites[index].header or flatReservationHeaderFlag):
      creditFlatAuxiliaryBlock(f, index, 1)

  const FlatAuxiliaryCycleCheckLimit = 4
    ## Do not consume the existing cold loop budget while waiting on an incomplete route.

  proc discoverFlatAuxiliaryCycle(f: var FlatFrame, header: uint32) =
    ## Keep one cold scout and count at most four walks against the Ring's sixteen.
    ## A retry needs new emitted nodes or cached edges. Ring retirement releases the
    ## cycle's share of the inventory, so Read-primary owners keep their loop budget.
    if f.mixedSource.cycleToken != 0 or
        f.mixedSource.count >= uint8(NativeMixedLoopCandidateLimit) or
        f.mixedSource.cycleChecks >= uint8(FlatAuxiliaryCycleCheckLimit) or
        int(f.mixedSource.checks)+int(f.mixedSource.cycleChecks) >= NativeMixedLoopReconstructionLimit:
      return
    let first = int(f.sites[int(header)])
    if first+ConnectedReadOpcodes.len > f.plan.facts.len: return
    let token = f.plan.facts[first].pc+1
    if f.mixedSource.cycleScout != 0 and f.mixedSource.cycleScout != token: return
    let nodes = uint32(f.handlers.len)
    let links = f.mixedSource.cycleLinks
    if f.mixedSource.cycleScout == token and f.mixedSource.cycleTriedNodes == nodes and
        f.mixedSource.cycleTriedLinks == links: return
    for index in 0..<ConnectedReadOpcodes.len:
      if f.plan.facts[first+index].opcode != ConnectedReadOpcodes[index]: return
    # Both fallthroughs must be linked before a reconstruction can reach the rest of the graph.
    let readTerminal = header+uint32(ConnectedReadOpcodes.len)-1
    let jump: FlatHandler = flatCachedJump[1]
    if int(readTerminal) >= f.handlers.len or f.handlers[int(readTerminal)] != jump: return
    let setupTerminal = f.arguments[int(readTerminal)].y+NativeReadContinuationSpan
    if int(setupTerminal) >= f.handlers.len or f.handlers[int(setupTerminal)] != jump: return
    f.mixedSource.cycleScout = token
    f.mixedSource.cycleTriedNodes = nodes
    f.mixedSource.cycleTriedLinks = links
    inc f.mixedSource.cycleChecks
    let cycle = buildFlatAuxiliaryCycle(f, token, f.auxiliaryHeat.primary.epoch)
    if cycle.read.complete and not nativeReadCycleObservationOverlaps(f.nativeSession, cycle):
      f.mixedSource.cycleToken = token
      observeFlatAuxiliaryCycle(f, cycle)

  when defined(pvmTypedAuxiliaryWitness):
    proc verifyColdFlatAuxiliaryScout(f: var FlatFrame, header: uint32) =
      ## Hold one real certified Tail edge cold, then publish exactly that cache progress.
      let source = f.mixedSource
      let heat = f.auxiliaryHeat
      let cycle = buildFlatAuxiliaryCycle(f, source.cycleToken, heat.primary.epoch)
      assert cycle.read.complete
      let terminal = cycle.layout.sites[NativeCycleRole.Tail].header+3
      let original = f.handlers[int(terminal)]
      assert original == flatBranch[173]
      f.handlers[int(terminal)] = flatUnresolvedBranch[173]
      defer:
        f.handlers[int(terminal)] = original
        f.mixedSource = source
        f.auxiliaryHeat = heat
      f.mixedSource.cycleToken = 0
      f.mixedSource.cycleScout = 0
      f.mixedSource.cycleChecks = 0
      for visit in 0..<32: discoverFlatAuxiliaryCycle(f, header)
      assert f.mixedSource.cycleChecks == 1 and f.mixedSource.cycleToken == 0
      f.handlers[int(terminal)] = original
      inc f.mixedSource.cycleLinks
      discoverFlatAuxiliaryCycle(f, header)
      assert f.mixedSource.cycleChecks == 2 and f.mixedSource.cycleToken == source.cycleToken
      echo "TYPED_AUX_COLD_SCOUT,32,1,2"

  proc reserveFlatAuxiliaryBlock(f: var FlatFrame, header: uint32, span: uint64) =
    ## Count only the eventual completion of an unpaid, fully reserved original block.
    if span == uint64(ConnectedReadOpcodes.len) and f.mixedSource.cycleToken == 0:
      discoverFlatAuxiliaryCycle(f, header)
      when defined(pvmTypedAuxiliaryWitness):
        if f.mixedSource.cycleToken != 0: verifyColdFlatAuxiliaryScout(f, header)
    for index in 0..<int(f.auxiliaryHeat.count):
      let site = f.auxiliaryHeat.sites[index]
      if site.header == header and uint64(site.span) == span:
        f.auxiliaryHeat.pending = uint8(index+1)
        return

  proc observeFlatAuxiliaryStoreGroup(f: var FlatFrame, header: uint32) =
    for index in 0..<int(f.auxiliaryHeat.count):
      let site = f.auxiliaryHeat.sites[index]
      if site.header == header and site.span == uint8(NativeCycleSpans[NativeCycleRole.Store]):
        creditFlatAuxiliaryBlock(f, index, NativeCycleGroupVisits)
        return

  proc finishFlatAuxiliaryInvocation*(f: var FlatFrame, successfulHalt: bool) =
    ## Rank exact settled work in the final live frame, after Read cleanup.
    ## A cycle needs 4,096 certified role attempts and at least one completed Read.
    ## The outside successor contributes no cycle heat. Rebuild all proofs before
    ## offering once under the exact key. Refusal cannot transfer heat to another call.
    defer: clearFlatAuxiliaryInvocation(f)
    let current = nativeInstalledKey(f.nativeSession)
    if f.mixedSource.chosenPrimary.kind == NativeKind.RegisterRing and
        f.mixedSource.chosenPrimary != current:
      resetFlatRingAuxiliarySource(f, current)
    # This policy requires actual current-call Ring work at the final boundary.
    if not successfulHalt or not f.auxiliaryHeat.valid or f.auxiliaryHeat.pending != 0 or
        f.mixedSource.chosenCount != 0 or not nativeInvocationUsed(f.nativeSession) or
        f.auxiliaryHeat.total > observedNativeWork(f.nativeSession): return
    let key = f.auxiliaryHeat.primary
    if not matchesNativeImage(f.nativeSession, key, NativeKind.RegisterRing) or
        f.mixedSource.epoch != key.epoch: return
    var work = default(array[NativeMixedLoopCandidateLimit, uint64])
    const cycleIndex = NativeMixedLoopCandidateLimit-1
    let loopCount = int(f.mixedSource.count)
    var completedRead = false
    for index in 0..<int(f.auxiliaryHeat.count):
      let site = f.auxiliaryHeat.sites[index]
      case site.kind
      of FlatAuxiliarySiteKind.Loop: work[int(site.role)] = site.attempts
      of FlatAuxiliarySiteKind.CycleRole:
        assert loopCount <= cycleIndex
        work[cycleIndex] += site.attempts # All sites were summed within the public quota.
        if site.role == uint8(ord(NativeCycleRole.Read)) and site.visits != 0:
          completedRead = true
      of FlatAuxiliarySiteKind.Outside: discard
    if loopCount <= cycleIndex and not completedRead: work[cycleIndex] = 0
    var requested = initNativeAuxiliaryPlan(key.epoch)
    var chosen = default(array[NativeMixedLoopEntryLimit, uint32])
    var chosenCycle = 0'u8
    when defined(pvmTypedAuxiliaryWitness):
      var rank = default(array[NativeAuxiliaryEntryLimit, uint64])
    for selection in 0..<NativeAuxiliaryEntryLimit:
      var best = -1
      var attempts = NativeInvocationFloor-1
      for index in 0..<work.len:
        if work[index] > attempts:
          best = index
          attempts = work[index]
      if best < 0: break
      work[best] = 0
      let slot = requested.len
      if best == cycleIndex and best >= loopCount:
        let token = f.mixedSource.cycleToken
        let cycle = buildFlatAuxiliaryCycle(f, token, key.epoch)
        if not cycle.read.complete or nativeReadCycleObservationOverlaps(f.nativeSession, cycle) or
            not requested.add(cycle): continue
        chosen[slot] = token
        chosenCycle = uint8(slot+1)
      else:
        let token = f.mixedSource.candidates[best]
        let proof = buildFlatMixedLoop(f, token-1, key.epoch)
        if not proof.complete or not mixedLoopDisjoint(f.nativeSession, proof) or
            not requested.add(proof): continue
        chosen[slot] = token
      when defined(pvmTypedAuxiliaryWitness): rank[slot] = attempts
    if requested.len != 0 and offerNativeAuxiliary(f.nativeSession, key, requested):
      f.mixedSource.chosen = chosen
      f.mixedSource.chosenCount = uint8(requested.len)
      f.mixedSource.chosenCycle = chosenCycle
      f.mixedSource.chosenPrimary = key
      when defined(pvmTypedAuxiliaryWitness):
        echo "TYPED_AUX_LAYOUT,", sizeof(FlatAuxiliaryHeat), ",", sizeof(FlatAuxiliaryPatch),
          ",", sizeof(FlatMixedLoopSource), ",", sizeof(NativeAuxiliaryLease), ",", sizeof(FlatFrame)
        echo "TYPED_AUX_HALT_OFFER,", key.ticket, ",", key.epoch, ",", requested.len,
          ",", f.auxiliaryHeat.total, ",", observedNativeWork(f.nativeSession)
        for index in 0..<requested.len:
          echo "TYPED_AUX_CHOICE,", index, ",", ord(requested.kind(uint8(index))),
            ",", chosen[index]-1, ",", rank[index]
        for index in 0..<int(f.auxiliaryHeat.count):
          let site = f.auxiliaryHeat.sites[index]
          echo "TYPED_AUX_HEAT,", ord(site.kind), ",", site.role, ",", site.header,
            ",", site.visits, ",", site.attempts

  proc flatAuxiliaryLoopEntry(f: var FlatFrame, off: uint32): uint32 {.noinline.} =
    let plan = f.auxiliaryPlan
    assert plan != nil and f.auxiliaryLease.ready
    for index in 0..<int(f.auxiliaryPatchCount):
      let patch = f.auxiliaryPatches[index]
      if patch.offset != off: continue
      assert plan[].kind(patch.slot) == NativeAuxiliaryKind.SelfLoop
      let slot = patch.slot
      template selected(entry, registers, context: untyped): untyped =
        enterBorrowedAuxiliaryLoop(entry, slot, registers, context)
      return enterFlatMixedLoop(f, off, plan[].loopProof(slot), addr f.auxiliaryLease, selected)
    abortNativeReceipt()

  proc flatAuxiliaryReadEntry(f: var FlatFrame, off: uint32): uint32 {.noinline.} =
    let plan = f.auxiliaryPlan
    assert plan != nil and f.auxiliaryLease.ready
    for index in 0..<int(f.auxiliaryPatchCount):
      let patch = f.auxiliaryPatches[index]
      if patch.offset != off: continue
      let original = patch.checked
      assert original != nil and plan[].kind(patch.slot) == NativeAuxiliaryKind.ReadCycle
      let proof {.cursor.} = plan[].cycleProof(patch.slot)
      let read = proof.read.info
      if read.epoch != nativeEpoch(f.nativeSession) or
          not matchesNativeImage(f.nativeSession, f.mixedSource.chosenPrimary,
              NativeKind.RegisterRing) or f.pricingKind != 0 or f.barrier != flatStop or
          not f.info.blockCharged or off != read.header+1 or
          f.reservation != (read.header or flatReservationHeaderFlag):
        return original(f, off)
      var context = flatCycleContext(f)
      var lastHeader = read.header
      result = runBorrowedAuxiliaryCycle(f.nativeSession, f.auxiliaryLease, patch.slot,
        proof, f.info.registers, context, lastHeader)
      when defined(pvmTypedAuxiliaryWitness):
        echo "TYPED_AUX_READ,", patch.slot, ",", context.lastCompleted, ",", context.paidRead,
          ",", context.visits[NativeCycleRole.Read], ",", context.visits[NativeCycleRole.Store]
      f.info.gas = MachineGas(context.gas)
      f.remaining = context.remaining
      if context.paidRead == 1:
        # The paid Read retries once with the live earlier stores and the original reservation.
        f.reservation = read.header or flatReservationHeaderFlag
        return original(f, off)
      f.info.blockCharged = false
      f.reservation = lastHeader or flatReservationHeaderFlag
      return
    abortNativeReceipt()

  proc planFlatAuxiliaryPatches(f: var FlatFrame, plan: var NativeAuxiliaryPlan,
      mask: uint8): bool =
    ## Capture the actual original handlers for at most eight occupied slots.
    ## Validate the full ledger and ABI tags before mutating the live checked stream.
    ## The caller owns plan storage and must restore the handlers before lease return.
    assert f.auxiliaryPatchCount == 0 and f.auxiliaryPlan == nil and f.auxiliaryLease.ready
    var patches = default(array[NativeAuxiliaryEntryLimit, FlatAuxiliaryPatch])
    var count = 0
    for index in 0..<plan.len:
      if (mask and (1'u8 shl index)) == 0: continue
      let slot = uint8(index)
      let kind = plan.kind(slot)
      if not auxiliaryEntryMatches(f.auxiliaryLease, slot, kind): return false
      let offset = if kind == NativeAuxiliaryKind.SelfLoop: plan.loopProof(slot).header
        else: plan.cycleProof(slot).read.info.header+1
      if int(offset) >= f.handlers.len: return false
      let checked = f.handlers[int(offset)]
      var installed: FlatHandler = flatAuxiliaryReadEntry
      if kind == NativeAuxiliaryKind.SelfLoop: installed = flatAuxiliaryLoopEntry
      if kind == NativeAuxiliaryKind.SelfLoop and checked != flatCharge: return false
      for primary in 0..<int(f.nativeInstallation.count):
        if f.nativeInstallation.patches[primary].offset == offset: return false
      for previous in 0..<count:
        if patches[previous].offset == offset: return false
      patches[count] = FlatAuxiliaryPatch(offset: offset, slot: slot,
        checked: checked, installed: installed)
      inc count
    if count == 0: return false
    when defined(pvmTypedAuxiliaryWitness):
      echo "TYPED_AUX_LEASE,", mask, ",", count, ",", auxiliaryCodeBytes(f.auxiliaryLease)
    f.auxiliaryPatches = patches
    f.auxiliaryPatchCount = uint8(count)
    f.auxiliaryPlan = addr plan
    for index in 0..<count:
      let patch = patches[index]
      let installed = patch.installed
      assert installed != nil
      f.handlers[int(patch.offset)] = installed
    true

  proc restoreFlatAuxiliaryPatches(f: var FlatFrame) =
    ## Restore every actual checked handler, including one saved beneath a quota barrier.
    ## Clear the local proof view before lease return can retire and unmap the image.
    for index in 0..<int(f.auxiliaryPatchCount):
      let patch = f.auxiliaryPatches[index]
      let checked = patch.checked
      let installed = patch.installed
      assert checked != nil and installed != nil
      restoreFlatTemporaryHandler(f, patch.offset, installed, checked)
    f.auxiliaryPatchCount = 0
    f.auxiliaryPlan = nil
