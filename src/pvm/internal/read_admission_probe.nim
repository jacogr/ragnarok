# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded one-call admission through checked terminals on read-capable native backends.
## The owning handler include supplies the private frame and checked terminal operations.

when declared(FlatFrame):
  const
    ReadProbeVisitFloor = 32768'u64 ## Minimum eligible complete visits in one invocation.

  func readProbeGuardOverlaps(f: FlatFrame, candidate: NativeReadBodyInfo): bool =
    ## Source aliases of an incumbent's checked successor are protected even at different physical nodes.
    let header = nativeReadObservationGuardHeader(f.nativeSession)
    if header == NativeEntryLimit: return false
    if int(header) >= f.sites.len: return true
    let first = f.sites[int(header)]
    if int(first) >= f.plan.facts.len: return true
    let span = f.plan.facts[int(first)].sourceCount
    if span == 0 or span > uint32(f.plan.facts.len)-first: return true
    candidate.first <= first+span-1 and first <= candidate.last

  func readProbeBodyGuardOverlaps(f: FlatFrame, body: NativeReadBody): bool =
    ## Optional continuation facts are part of the candidate's complete source authority.
    if readProbeGuardOverlaps(f, body.info): return true
    let next = body.continuationInfo
    if next.terminal == 0: return false
    let last = body.info.last
    if last > high(uint32)-NativeReadContinuationSpan: return true
    readProbeGuardOverlaps(f, NativeReadBodyInfo(first: last+1,
      last: last+NativeReadContinuationSpan))

  when NativeReadCycleEnabled:
    func readProbeCycleGuardOverlaps(f: FlatFrame, cycle: NativeReadCycle): bool =
      ## Every connected role's immutable facts must avoid the incumbent's checked successor.
      for role in NativeCycleRole:
        let site = cycle.layout.sites[role]
        let span = uint32(NativeCycleSpans[role])
        if site.first > high(uint32)-span: return true
        if readProbeGuardOverlaps(f, NativeReadBodyInfo(first: site.first,
            last: site.first+span-1)): return true
      false

  proc observeReadProbeHeader(f: var FlatFrame, header: uint32) =
    ## Cheap immutable shape filtering precedes one bounded inspection of a cached checked header.
    if not f.readProbe.observing or not f.readProbe.later or
        f.readProbe.inspected == ReadProbeWalkLimit or nativeInvocationUsed(f.nativeSession): return
    let first = int(f.sites[int(header)])
    if first < 0 or first >= f.plan.facts.len: return
    let fact = f.plan.facts[first]
    if fact.opcode != 2 or fact.sourceCount notin 4'u32..NativeReadFactLimit: return
    let count = int(fact.sourceCount)
    if count > f.plan.facts.len-first or f.plan.facts[first+count-1].opcode != 1: return
    discoverReadProbe(f, header, fact.pc)

  template observeReadProbeTerminal(f: var FlatFrame, off: uint32, slot: int,
      observer: FlatHandler, destination: var uint32) =
    ## Settle the checked terminal and count only complete eligible visits for this exact slot.
    assert f.readProbe.observing
    let header = f.readProbe.candidates[slot].header
    let full = f.barrier == flatStop and f.info.blockCharged and
      f.reservation == (header or flatReservationHeaderFlag)
    if f.readProbe.candidates[slot].resolved:
      destination = flatCachedJump[1](f, off)
    else:
      # The cold resolver can append more candidates and self-patches only on success.
      destination = flatJump[1](f, off)
      if destination != flatStop:
        f.readProbe.candidates[slot].resolved = true
        f.handlers[int(off)] = observer
    if not full or destination == flatStop: return
    assert f.remaining <= f.readProbe.segmentBudget
    # Initial admission observes its first segment; later admission retains settled work across callbacks.
    let segmentWork = f.readProbe.segmentBudget-f.remaining
    if f.readProbe.priorWork > high(uint64)-segmentWork: return
    let work = f.readProbe.priorWork+segmentWork
    let maximum = high(uint64) div uint64(NativeReadFactLimit)
    if work < NativeInvocationFloor: return
    if f.readProbe.candidates[slot].eligible < maximum:
      inc f.readProbe.candidates[slot].eligible

  proc readProbeTerminal(f: var FlatFrame, off: uint32): uint32 =
    ## Ordinary observations search only the ordinary candidate range.
    var slot = 0
    while slot < f.readProbe.count and f.readProbe.candidates[slot].terminal != off:
      inc slot
    assert slot < f.readProbe.count
    observeReadProbeTerminal(f, off, slot, readProbeTerminal, result)

  when NativeReadCycleEnabled:
    proc protectedReadProbeCharge(f: var FlatFrame, off: uint32): uint32 =
      ## Use the original reservation and body dispatch. Only complete attempts can count.
      flatReserveImpl(f, off, true, false)
      let next = off+1
      let selected = f.handlers[int(next)]
      selected(f, next)

    proc settleProtectedReadSegment(f: var FlatFrame) =
      ## Restore the original header before classifiers and retain only settled eligible segment visits.
      ## The sealed straight-line Read contains no Host or Halt. A fully reserved Read can reach
      ## either exit only after its own fallthrough has completed. An interruption inside Read
      ## ends the segment with a refusal and cannot contribute nomination evidence.
      if not f.readProbe.observing or not f.readProbe.protectedActive: return
      let header = f.readProbe.candidates[ReadProbeSlots].header
      assert f.handlers[int(header)] == protectedReadProbeCharge
      f.handlers[int(header)] = flatCharge
      f.readProbe.protectedActive = false
      if f.reason == oracle.StepError.None and f.attemptedExit and
          f.exit in {oracle.StepExit.Halt, oracle.StepExit.Host}:
        # Full reservations spend disjoint source attempts, so the raw count cannot overflow.
        let ceiling = high(uint64) div uint64(NativeReadFactLimit)
        f.readProbe.candidates[ReadProbeSlots].eligible = min(
          f.readProbe.candidates[ReadProbeSlots].eligible, ceiling)
      else:
        # A failed segment cannot nominate, including a partially executed Read.
        f.readProbe.candidates[ReadProbeSlots].eligible = 0

    proc discoverProtectedRead(f: var FlatFrame, header, pc: uint32) =
      ## Give one exact-length, source-matched Read a spare observation after saturation.
      assert f.readProbe.count == ReadProbeSlots
      if f.readProbe.protectedTried or f.readProbe.inspected == ReadProbeWalkLimit: return
      let first = int(f.sites[int(header)])
      if first > f.plan.facts.len-ConnectedReadOpcodes.len or
          f.plan.facts[first].sourceCount != uint32(ConnectedReadOpcodes.len): return
      inc f.readProbe.inspected
      for index, opcode in ConnectedReadOpcodes:
        # Immutable opcodes filter discovery; the full route is certified after observation.
        if f.plan.facts[first+index].opcode != opcode: return
      f.readProbe.protectedTried = true
      if f.readProbe.inspected == ReadProbeWalkLimit: return
      inc f.readProbe.inspected
      let body = buildFlatReadBody(f, pc, f.readProbe.epoch)
      if not body.complete or body.info.header != header: return
      let info = body.info
      if f.readProbe.later and (nativeReadObservationOverlaps(f.nativeSession, info) or
          readProbeGuardOverlaps(f, info)): return
      for index in 0..<ReadProbeSlots:
        # A cold resolver can reach this branch while an ordinary wrapper is settling.
        if f.readProbe.candidates[index].terminal == info.terminal: return
      f.readProbe.candidates[ReadProbeSlots] = ReadProbeCandidate(pc: pc, header: header,
        terminal: info.terminal, sourceFacts: info.last-info.first+1, operations: body.len)
      f.readProbe.protectedInstalled = true
      f.readProbe.protectedActive = true
      let outstanding = if f.readProbe.priorWork >= NativeInvocationFloor: 0'u64
        else: NativeInvocationFloor-f.readProbe.priorWork
      f.readProbe.protectedCountable = outstanding <= f.readProbe.segmentBudget
      f.readProbe.protectedRemainingLimit = if f.readProbe.protectedCountable:
        f.readProbe.segmentBudget-outstanding else: 0'u64
      f.handlers[int(header)] = protectedReadProbeCharge

  proc discoverReadProbe(f: var FlatFrame, header, pc: uint32) =
    ## Bound certificate walks per call and deduplicate cached headers during later discovery.
    if f.readProbe.inspected == ReadProbeWalkLimit: return
    when NativeReadCycleEnabled:
      if f.readProbe.count == ReadProbeSlots and f.readProbe.protectedTried: return
    else:
      if f.readProbe.count == ReadProbeSlots: return
    if f.readProbe.later and not admitNativeReadDiscoveryHeader(f.nativeSession, header): return
    when NativeReadCycleEnabled:
      if f.readProbe.count == ReadProbeSlots:
        discoverProtectedRead(f, header, pc)
        return
    if f.readProbe.count == ReadProbeSlots or f.readProbe.inspected == ReadProbeWalkLimit: return
    inc f.readProbe.inspected
    let body = buildFlatReadBody(f, pc, f.readProbe.epoch)
    if not body.complete or body.info.header != header: return
    let info = body.info
    if f.readProbe.later and (nativeReadObservationOverlaps(f.nativeSession, info) or
          readProbeGuardOverlaps(f, info)): return
    f.readProbe.candidates[f.readProbe.count] = ReadProbeCandidate(pc: pc, header: header,
      terminal: info.terminal, sourceFacts: info.last-info.first+1, operations: body.len,
      resolved: f.handlers[int(info.terminal)] == flatCachedJump[1])
    inc f.readProbe.count
    f.handlers[int(info.terminal)] = readProbeTerminal

  proc beginReadProbe*(f: var FlatFrame, budget: uint64) =
    ## Initial selection observes the fresh first segment; replacement also observes restored cached code.
    if f.pricingKind != 0 or f.plan.allowNative or f.info.blockCharged:
      return
    let later = nativeReplacementObservation(f.nativeSession)
    if f.handlers.len != 0 and not later: return
    f.readProbe.epoch = nativeReadAdmissionEpoch(f.nativeSession)
    if f.readProbe.epoch == 0: return
    if later: beginNativeReadDiscovery(f.nativeSession)
    f.readProbe.callActive = true
    f.readProbe.later = later
    f.readProbe.observing = true
    f.readProbe.segmentBudget = budget

  proc resumeReadProbeSegment*(f: var FlatFrame, budget: uint64) =
    ## Rebind only known bounded observers, preserving dedup, inspection and visit state across callbacks.
    if f.readProbe.observing or not f.readProbe.callActive or not f.readProbe.later or
        not nativeReplacementObservation(f.nativeSession): return
    f.readProbe.segmentBudget = budget
    f.readProbe.priorWork = observedNativeWork(f.nativeSession)
    f.readProbe.observing = true
    for index in 0..<f.readProbe.count:
      let terminal = f.readProbe.candidates[index].terminal
      let selected = f.handlers[int(terminal)]
      assert selected == flatJump[1] or selected == flatCachedJump[1]
      f.readProbe.candidates[index].resolved = selected == flatCachedJump[1]
      f.handlers[int(terminal)] = readProbeTerminal
    when NativeReadCycleEnabled:
      if f.readProbe.protectedInstalled:
        let header = f.readProbe.candidates[ReadProbeSlots].header
        assert f.handlers[int(header)] == flatCharge
        let outstanding = if f.readProbe.priorWork >= NativeInvocationFloor: 0'u64
          else: NativeInvocationFloor-f.readProbe.priorWork
        f.readProbe.protectedCountable = outstanding <= budget
        f.readProbe.protectedRemainingLimit = if outstanding <=
            budget: budget-outstanding else: 0'u64
        f.readProbe.protectedActive = true
        f.handlers[int(header)] = protectedReadProbeCharge

  proc endReadProbeSegment*(f: var FlatFrame) =
    ## Restore each original terminal before callbacks, replacement, exit or stream retention.
    if not f.readProbe.observing: return
    when NativeReadCycleEnabled:
      # Early runFlat refusals still restore a rebound protected header exactly once.
      settleProtectedReadSegment(f)
    for index in 0..<f.readProbe.count:
      # runFlat has already restored its temporary step barrier on the terminal slot.
      let terminal = f.readProbe.candidates[index].terminal
      let handler = f.handlers[int(terminal)]
      assert handler == readProbeTerminal
      if f.readProbe.candidates[index].resolved:
        f.handlers[int(terminal)] = flatCachedJump[1]
      else:
        f.handlers[int(terminal)] = flatJump[1]
    f.readProbe.observing = false

  when NativeReadCycleEnabled:
    proc nominateProtectedRead(f: FlatFrame, share: uint64): bool =
      ## Only a fully certified protected route can displace ordinary nomination.
      if not f.readProbe.protectedInstalled: return false
      let candidate = f.readProbe.candidates[ReadProbeSlots]
      if candidate.eligible < ReadProbeVisitFloor or
          candidate.eligible*uint64(candidate.sourceFacts) < share: return false
      var body = buildFlatReadBody(f, candidate.pc, f.readProbe.epoch)
      if not body.complete or body.len != candidate.operations: return false
      let info = body.info
      if info.header != candidate.header or info.terminal != candidate.terminal or
          f.handlers[int(candidate.terminal)] != flatCachedJump[1]: return false
      if not extendFlatReadBody(f, body): return false
      let cycle = buildFlatReadCycle(f, body)
      if not cycle.read.complete: return false
      if f.readProbe.later and (nativeReadCycleObservationOverlaps(f.nativeSession, cycle) or
          readProbeCycleGuardOverlaps(f, cycle)): return false
      nominateNativeReadCycle(f.nativeSession, cycle)
      true

  proc finishReadProbe*(f: FlatFrame, success: bool) =
    ## Revalidate and nominate only the best qualified candidate after a full checked halt.
    assert not f.readProbe.observing
    if f.readProbe.epoch == 0 or not success or f.reason != oracle.StepError.None or
        f.exit != oracle.StepExit.Halt or not f.attemptedExit: return
    let settled = observedNativeWork(f.nativeSession)
    if settled < NativeInvocationFloor: return
    let share = (settled-1) div 8+1
    var best = -1
    var bestScore = 0'u64
    for index in 0..<f.readProbe.count:
      # Arithmetic fits by the visit ceiling and the certificate's 32-fact limit.
      let candidate = f.readProbe.candidates[index]
      if candidate.eligible < ReadProbeVisitFloor or
          candidate.eligible*uint64(candidate.sourceFacts) < share: continue
      let score = candidate.eligible*uint64(candidate.operations)
      if score > bestScore or (score == bestScore and best >= 0 and
          candidate.pc < f.readProbe.candidates[best].pc):
        best = index
        bestScore = score
    when NativeReadCycleEnabled:
      if nominateProtectedRead(f, share): return
    if best < 0: return
    let winner = f.readProbe.candidates[best]
    var body = buildFlatReadBody(f, winner.pc, f.readProbe.epoch)
    if not body.complete or body.len != winner.operations: return
    let info = body.info
    if info.header != winner.header or info.terminal != winner.terminal: return
    if f.handlers[int(winner.terminal)] != flatCachedJump[1]: return
    discard extendFlatReadBody(f, body)
    when NativeReadCycleEnabled:
      let cycle = buildFlatReadCycle(f, body)
      if cycle.read.complete and
          (not f.readProbe.later or (not nativeReadCycleObservationOverlaps(f.nativeSession,
              cycle) and
            not readProbeCycleGuardOverlaps(f, cycle))):
        nominateNativeReadCycle(f.nativeSession, cycle)
        return
    if f.readProbe.later and readProbeBodyGuardOverlaps(f, body): return
    nominateNativeRead(f.nativeSession, body)

  proc finishNativeReadObservation*(f: var FlatFrame, success: bool) =
    ## Qualify the returned halt, then restore and revalidate the checked stream before retirement.
    assert not f.readProbe.observing
    when NativeReadCycleEnabled:
      assert not f.readProbe.protectedActive
    let key = nativeInstalledKey(f.nativeSession)
    let qualified = success and f.reason == oracle.StepError.None and
      f.exit == oracle.StepExit.Halt and f.attemptedExit and f.pricingKind == 0 and
      f.nativeInstallation.count != 0 and f.nativeInstallation.key == key and key.ticket != 0
    completeNativeObservation(f.nativeSession, qualified)
    if not qualified:
      discardNativeReplacement(f.nativeSession)
      return
    let info = nativeReplacementReadInfo(f.nativeSession)
    if info.epoch == 0: return
    assert f.barrier == flatStop
    flatRestoreNativeInstallation(f)
    var valid = false
    if int(info.first) < f.plan.facts.len:
      var body = buildFlatReadBody(f, f.plan.facts[int(info.first)].pc, info.epoch)
      if body.complete:
        when NativeReadCycleEnabled:
          if nativeReplacementIsCycle(f.nativeSession):
            if extendFlatReadBody(f, body):
              let cycle = buildFlatReadCycle(f, body)
              valid = not readProbeCycleGuardOverlaps(f, cycle) and
                validateNativeReplacementCycle(f.nativeSession, cycle)
          else:
            let extended = nativeReplacementContinuation(f.nativeSession).terminal != 0
            if not extended or extendFlatReadBody(f, body):
              valid = not readProbeBodyGuardOverlaps(f, body) and
                validateNativeReplacementRead(f.nativeSession, body)
        else:
          let extended = nativeReplacementContinuation(f.nativeSession).terminal != 0
          if not extended or extendFlatReadBody(f, body):
            valid = not readProbeBodyGuardOverlaps(f, body) and
              validateNativeReplacementRead(f.nativeSession, body)
    if valid and retireNativeForReadReplacement(f.nativeSession, key): return
    # The incumbent remains mapped if revalidation or retirement fails.
    # Rebind it only through its unchanged source certificate.
    discardNativeReplacement(f.nativeSession)
    installNative(f)
