# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded one-call admission through checked terminals on read-capable native backends.
## The owning handler include supplies the private frame and checked terminal operations.

when declared(FlatFrame):
  const
    ReadProbeWalkLimit = 128        ## Each attempted certificate walks at most NativeReadFactLimit facts.
    ReadProbeVisitFloor = 32768'u64 ## Minimum eligible complete visits in one invocation.

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
    # Only the first segment is observed. The complete reservation has now settled.
    let work = f.readProbe.segmentBudget-f.remaining
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
      flatReserveImpl(f, off, true)
      let next = off+1
      let selected = f.handlers[int(next)]
      selected(f, next)

    proc settleProtectedReadSegment(f: var FlatFrame) =
      ## Restore the original header before classifiers and retain only settled first-segment visits.
      ## The sealed straight-line Read contains no Host or Halt. A fully reserved Read can reach
      ## either exit only after its own fallthrough has completed. An interruption inside Read
      ## ends the segment with a refusal and cannot contribute nomination evidence.
      if not f.readProbe.observing or not f.readProbe.protectedInstalled: return
      let header = f.readProbe.candidates[ReadProbeSlots].header
      assert f.handlers[int(header)] == protectedReadProbeCharge
      f.handlers[int(header)] = flatCharge
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
      for index in 0..<ReadProbeSlots:
        # A cold resolver can reach this branch while an ordinary wrapper is settling.
        if f.readProbe.candidates[index].terminal == info.terminal: return
      f.readProbe.candidates[ReadProbeSlots] = ReadProbeCandidate(pc: pc, header: header,
        terminal: info.terminal, sourceFacts: info.last-info.first+1, operations: body.len)
      f.readProbe.protectedInstalled = true
      assert f.readProbe.segmentBudget >= NativeInvocationFloor
      f.readProbe.protectedRemainingLimit = f.readProbe.segmentBudget-NativeInvocationFloor
      f.handlers[int(header)] = protectedReadProbeCharge

  proc discoverReadProbe(f: var FlatFrame, header, pc: uint32) =
    ## Keep the four ordinary probes independent of the optional protected observation.
    when NativeReadCycleEnabled:
      if f.readProbe.count == ReadProbeSlots:
        discoverProtectedRead(f, header, pc)
        return
    if f.readProbe.count == ReadProbeSlots or f.readProbe.inspected == ReadProbeWalkLimit: return
    inc f.readProbe.inspected
    let body = buildFlatReadBody(f, pc, f.readProbe.epoch)
    if not body.complete or body.info.header != header: return
    let info = body.info
    f.readProbe.candidates[f.readProbe.count] = ReadProbeCandidate(pc: pc, header: header,
      terminal: info.terminal, sourceFacts: info.last-info.first+1, operations: body.len,
      resolved: f.handlers[int(info.terminal)] == flatCachedJump[1])
    inc f.readProbe.count
    f.handlers[int(info.terminal)] = readProbeTerminal

  proc beginReadProbe*(f: var FlatFrame, budget: uint64) =
    ## Arm only the fresh, uncharged first segment. Public host resumes retain the paid bit.
    if f.handlers.len != 0 or f.pricingKind != 0 or f.plan.allowNative or f.info.blockCharged:
      return
    f.readProbe.epoch = nativeReadAdmissionEpoch(f.nativeSession)
    if f.readProbe.epoch == 0: return
    f.readProbe.observing = true
    f.readProbe.segmentBudget = budget

  proc endReadProbeSegment*(f: var FlatFrame) =
    ## Restore each original terminal before callbacks, replacement, exit or stream retention.
    if not f.readProbe.observing: return
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
      if cycle.read.complete:
        nominateNativeReadCycle(f.nativeSession, cycle)
        return
    nominateNativeRead(f.nativeSession, body)
