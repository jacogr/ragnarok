# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded one-call admission through checked terminals on read-capable native backends.
## The owning handler include supplies the private frame and checked terminal operations.
when declared(FlatFrame):
  const
    ReadProbeWalkLimit = 128        ## Each attempted certificate walks at most NativeReadFactLimit facts.
    ReadProbeVisitFloor = 32768'u64 ## Minimum eligible complete visits in one invocation.

  proc readProbeTerminal(f: var FlatFrame, off: uint32): uint32 =
    ## Execute the original terminal first. Only a selected candidate incurs an observation.
    var slot = 0
    while slot < f.readProbe.count and f.readProbe.candidates[slot].terminal != off:
      inc slot
    assert slot < f.readProbe.count and f.readProbe.observing
    let header = f.readProbe.candidates[slot].header
    let full = f.barrier == flatStop and f.info.blockCharged and
      f.reservation == (header or flatReservationHeaderFlag)
    if f.readProbe.candidates[slot].resolved:
      result = flatCachedJump[1](f, off)
    else:
      # The cold resolver can append more candidates and self-patches only on success.
      result = flatJump[1](f, off)
      if result != flatStop:
        f.readProbe.candidates[slot].resolved = true
        f.handlers[int(off)] = readProbeTerminal
    if not full or result == flatStop: return
    assert f.remaining <= f.readProbe.segmentBudget
    # Only the first segment is observed. The complete reservation has now settled.
    let work = f.readProbe.segmentBudget-f.remaining
    let maximum = high(uint64) div uint64(NativeReadFactLimit)
    if work < NativeInvocationFloor: return
    if f.readProbe.candidates[slot].eligible < maximum:
      inc f.readProbe.candidates[slot].eligible

  proc discoverReadProbe(f: var FlatFrame, header, pc: uint32) =
    ## Bound full certificate work and retain at most four temporary terminal probes.
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
      assert f.handlers[int(terminal)] == readProbeTerminal
      if f.readProbe.candidates[index].resolved:
        f.handlers[int(terminal)] = flatCachedJump[1]
      else:
        f.handlers[int(terminal)] = flatJump[1]
    f.readProbe.observing = false

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
    if best < 0: return
    let winner = f.readProbe.candidates[best]
    var body = buildFlatReadBody(f, winner.pc, f.readProbe.epoch)
    if not body.complete or body.len != winner.operations: return
    let info = body.info
    if info.header != winner.header or info.terminal != winner.terminal: return
    if f.handlers[int(winner.terminal)] != flatCachedJump[1]: return
    discard extendFlatReadBody(f, body)
    nominateNativeRead(f.nativeSession, body)
