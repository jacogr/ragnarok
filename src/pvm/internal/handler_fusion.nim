# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included by the exclusive handler stream. An observed header only ranks a candidate.
## The copied block must reproduce original operands, paid extent and positive static edges.
## A full ranking reserves a bounded share of the graph for verified unconditional successors.
## Dynamic entry permission comes only from the admitted original jump table; live checked tags
## and immutable native entries must both agree before an indirect terminal can complete natively.
## The primary retains its handlers. Fusion patches only disjoint source-proven reservation
## headers during one segment and restores each exact predecessor before releasing the arena.
## Existing combined register/branch workers keep their separately addressable original nodes.
## Immutable source reconstruction lives in handler_fusion_source. This adapter proves the
## current checked layout and ownership before assigning physical targets and fallback sites.
## Checked-worker identities grant overlay compatibility only; they never define the copied IR.

when declared(FlatFrame):
  when defined(pvmSharedAsyncWitness):
    var refuseFusionTrainingAllocation {.threadvar.}: bool

    proc refuseNextFusionTrainingAllocation*() =
      ## Exercise optional profiling allocation refusal through the real prepared callback boundary.
      refuseFusionTrainingAllocation = true

    proc allowFusionTrainingAllocation(): bool =
      ## Consume the one-shot witness before the ordinary allocation; refusal must keep execution checked.
      result = not refuseFusionTrainingAllocation
      refuseFusionTrainingAllocation = false

  func fusionBranchHandler(opcode: byte): nil FlatHandler =
    ## Accept only the already resolved branch with the original GP predicate.
    case opcode
    of 81: flatBranch[81]
    of 82: flatBranch[82]
    of 83: flatBranch[83]
    of 84: flatBranch[84]
    of 85: flatBranch[85]
    of 86: flatBranch[86]
    of 87: flatBranch[87]
    of 88: flatBranch[88]
    of 89: flatBranch[89]
    of 90: flatBranch[90]
    of 170: flatBranch[170]
    of 171: flatBranch[171]
    of 172: flatBranch[172]
    of 173: flatBranch[173]
    of 174: flatBranch[174]
    of 175: flatBranch[175]
    else: nil

  func fusionHeaderWorker(handler: FlatHandler): bool =
    ## Classify reservation workers only; binding still proves the complete source and specialized shape.
    handler == flatCharge or handler == flatChargedAdjacent[false]

  func fusionSourceHeader(f: FlatFrame, header: uint32, pc: CodeAddress): bool =
    ## Narrow only an in-program logical target; physical permission remains with the checked PC map.
    if f.plan == nil or uint64(pc) >= uint64(f.plan.codeBytes): return false
    flatSourceHeader(f, header, uint32(uint64(pc)))

  proc bindFlatFusion(f: FlatFrame, off: uint32, item: var NativeFusionBlock): bool =
    ## Bind independent original-source IR to the exclusive checked stream. A refused block stays
    ## checked and leaves the output untouched. No candidate executes or changes guest/native state.
    if uint64(off) >= uint64(f.handlers.len) or uint64(off) >= uint64(f.sites.len) or
        not fusionHeaderWorker(f.handlers[int(off)]): return false
    let ordinal = f.sites[int(off)]
    if uint64(ordinal) >= uint64(f.plan.facts.len): return false
    var entry = default(FlatFact)
    if not tryReadFlatFact(f, int(ordinal), entry): return false
    let pc = entry.pc
    var originalSource = default(FusionSourceBlock)
    if not decodeFusionSource(f.plan, CodeAddress(uint64(pc)), originalSource): return false
    var header = 0'u32
    var source = default(FlatSourceInterval)
    var summary = default(FlatSourceSummary)
    if not flatCompleteOriginalHeader(f, pc, NativeReadFactLimit, header, source): return false
    if header != off or not flatWalkCompleteSource(f, header, source, summary): return false
    var first = default(FlatFact)
    var terminal = default(FlatFact)
    if not tryReadFlatFact(f, int(source.first), first) or
        not tryReadFlatFact(f, int(source.last), terminal): return false
    if originalSource.first != source.first or originalSource.span != source.span or
        originalSource.bodyCount+1 != summary.operations or originalSource.price != source.price or
        uint64(originalSource.terminalPc) != uint64(terminal.pc): return false
    if f.handlers[int(off)] != flatCharge:
      # The adjacent worker hard-codes these two source operations. Its identity alone
      # cannot grant native authority to a different otherwise valid original block.
      if source.span != 2 or source.last != source.first+1 or
          first.opcode != 132 or
          terminal.opcode != 81: return false
      if f.handlers[int(summary.terminal)] != flatBranch[81]: return false
    if nativeReadObservationOverlaps(f.nativeSession, NativeReadBodyInfo(header: off,
        terminal: summary.terminal, first: source.first, last: source.last,
        epoch: nativeEpoch(f.nativeSession))): return false
    var bound = NativeFusionBlock(header: off, terminal: summary.terminal,
      first: originalSource.first,
      span: originalSource.span, price: originalSource.price, operations: originalSource.operations,
      guards: originalSource.guards, targets: [NativeEntryFailure, NativeEntryFailure])
    let priceIndex = first.priceIndex
    var node = off+1
    for index in source.first..source.last:
      var fact = default(FlatFact)
      if not tryReadFlatFact(f, int(index), fact): return false
      if fact.priceIndex != priceIndex or uint64(fact.pc) != uint64(
          originalSource.locations[int(index-source.first)]): return false
      let decoded = instruction(f.plan.source, CodeAddress(uint64(fact.pc)))
      if decoded.error != ProgramError.None: return false
      let original = decoded.value
      if original.opcode != fact.opcode or
          uint64(original.address)+1+uint64(original.skip) != uint64(fact.next): return false
      if fact.opcode == 2: continue
      var payload = default(FlatSourcePayload)
      if not tryFlatSourcePayload(decoded, payload): return false
      let args = f.arguments[int(node)]
      let worker = f.handlers[int(node)]
      if node != summary.terminal:
        if args != payload.args: return false
        if worker != payload.handler:
          # Fused scalar and chained memory handlers retain original individual sites.
          let paired = if isRegisterOpcode(fact.opcode): flatRegisterPairHandler(fact.opcode)
            else: flatMemoryPairHandler(fact.opcode)
          let byteLoad = fact.opcode == 124 and (worker == flatOrByteUpdate or
            worker == flatMemoryWorker[1, true, false, true, false, true, true])
          if not byteLoad and (paired == nil or worker != paired):
            var combinedBranch = false
            if index+1 == source.last and node+1 == summary.terminal and fact.opcode == 131:
              # Both workers retain the original terminal record, which is checked below.
              # Direct comparisons avoid the typed-local lowering failure tracked as NIM-010.
              var successor = default(FlatFact)
              if not tryReadFlatFact(f, int(index+1), successor): return false
              let branch = successor.opcode
              if branch == 83:
                combinedBranch = worker == flatRegisterBranchCold[131, 83] or
                    worker == flatFusedRegisterBranch[131, 83]
              elif branch == 88:
                combinedBranch = worker == flatRegisterBranchCold[131, 88] or
                    worker == flatFusedRegisterBranch[131, 88]
              if combinedBranch:
                # A combined checked worker owns this exact cached terminal, not an opaque paid fallback.
                let cached = fusionBranchHandler(branch)
                if cached == nil or f.handlers[int(summary.terminal)] != cached: return false
            if not combinedBranch:
              if index >= source.last or node+1 >= summary.terminal or
                  f.sites[int(node+1)] != index+1: return false
              var successor = default(FlatFact)
              if not tryReadFlatFact(f, int(index+1), successor): return false
              let fused = flatFusedRegisterHandler(fact.opcode, successor.opcode)
              if fused == nil or worker != fused: return false
      elif fact.opcode in [1'u8, 40]:
        # The sealed original destination proves the edge once the cached operand
        # is a positive node for that exact original source. Unresolved workers
        # still carry a guest PC. Their identity must be excluded.
        let cached = if fact.opcode == 1: worker == flatCachedJump[1]
          else: worker == flatCachedJump[40]
        if cached and originalSource.targetValid[0] and
            fusionSourceHeader(f, args.y, originalSource.targets[0]):
          bound.targets[0] = args.y
          bound.branch = originalSource.terminal
      elif fact.opcode == 80:
        # Link the cached edge only if its register and immediate match the original write.
        if worker == flatCachedJump[80] and originalSource.targetValid[0] and
            fusionSourceHeader(f, args.y, originalSource.targets[0]):
          if args.slots != payload.args.slots or args.x != payload.args.x: return false
          bound.targets[0] = args.y
          bound.branch = originalSource.terminal
      elif fact.opcode in [50'u8, 180]:
        # The exact original dynamic worker/operands are required; execution still guards the live cache.
        if worker != payload.handler or args != payload.args: return false
        bound.branch = originalSource.terminal
      else:
        let cached = fusionBranchHandler(fact.opcode)
        if cached != nil and worker == cached:
          let yes = uint32(args.x shr 32)
          let no = args.y
          let mask = 0xffffffff'u64
          if args.slots != payload.args.slots or (args.x and mask) != (payload.args.x and mask) or
              not originalSource.targetValid[0] or not originalSource.targetValid[1] or
              not fusionSourceHeader(f, yes, originalSource.targets[1]) or
              not fusionSourceHeader(f, no, originalSource.targets[0]): return false
          bound.targets = [no, yes]
          bound.branch = originalSource.terminal
      inc node
    if not bound.complete: return false
    item = bound
    true

  proc sampleFlatFusion(probe: var FlatFusionProbe, header: uint32) {.noinline.} =
    ## Sparse bounded counts. The pseudorandom interval avoids lockstep with guest loops.
    var seed = probe.seed
    seed = seed xor (seed shl 13)
    seed = seed xor (seed shr 17)
    seed = seed xor (seed shl 5)
    probe.seed = seed
    probe.down = 1+(seed and 63)
    if probe.taken == FlatFusionSampleLimit: return
    inc probe.taken
    if header >= NativeEntryLimit: return
    let token = header+1
    let start = (token*0x9e3779b9'u32) shr 22
    var empty = -1
    for index in 0'u32..3'u32:
      let slot = int((start+index) and 1023)
      if probe.samples[slot].token == token:
        inc probe.samples[slot].count
        return
      if probe.samples[slot].token == 0 and empty < 0: empty = slot
    if empty >= 0:
      # Search the entire bucket first: cancellation can leave a hole before an existing key.
      probe.samples[empty] = FlatFusionSample(token: token, count: 1)
      return
    # Cold first arrivals cannot permanently exclude later hot regions. Four-way cancellation
    # only subtracts observations, so retained counts remain lower bounds on actual source visits.
    for index in 0'u32..3'u32:
      let slot = int((start+index) and 1023)
      if probe.samples[slot].count > 0: dec probe.samples[slot].count
      if probe.samples[slot].count == 0: probe.samples[slot].token = 0

  proc observeFlatFusion(probe: var FlatFusionProbe, header: uint32) {.inline.} =
    ## Keep the ordinary dispatcher free of sampling state outside the training segment.
    if probe.taken < FlatFusionSampleLimit:
      dec probe.down
      if probe.down == 0: sampleFlatFusion(probe, header)

  func liveFlatFusionTraining(f: FlatFrame): bool =
    ## Coordinates remain meaningful only for the exact immutable source, epoch and prefix ABI.
    if f.fusionTraining.len != 1 or f.plan == nil: return false
    let retained {.cursor.} = f.fusionTraining[0]
    if retained.segments == 0 or retained.segments >= FlatFusionTrainingSegments or
        retained.probe.taken >= FlatFusionSampleLimit or retained.probe.down == 0 or
        retained.probe.down > 64:
      return false
    let epoch = nativeEpoch(f.nativeSession)
    if epoch == 0 or retained.epoch != epoch or retained.owner != flatPlanIdentity(
        f.plan): return false
    let key = nativeInstalledKey(f.nativeSession)
    key.ticket != 0 and key.epoch == epoch and key.kind == NativeKind.PurePrefix

  func continueFlatFusionTraining(f: FlatFrame, probe: FlatFusionProbe, segments: uint32): bool =
    ## Host exits preserve source counts through later phases until either fixed window budget ends.
    ## Ranking needs 4096 samples, but that minimum is not evidence that observation is representative.
    f.reason == oracle.StepError.None and f.exit == oracle.StepExit.Host and
      f.preparationFailure == FlatError.None and probe.taken < FlatFusionSampleLimit and
      segments < FlatFusionTrainingSegments

  proc markFlatIndirectEntries(f: FlatFrame, blocks: var seq[NativeFusionBlock]): bool =
    ## One pass over the already admitted jump table marks source-backed entry permission.
    ## A fixed half-full PC map avoids multiplying table length by graph size; no guest execution occurs.
    var map = default(array[NativeFusionSlotLimit, uint64])
    for index in 0..<blocks.len:
      var fact = default(FlatFact)
      if not tryReadFlatFact(f, int(blocks[index].first), fact): return false
      let pc = fact.pc
      if pc == high(uint32): continue
      let token = pc+1
      var at = nativeFusionSlot(token)
      while map[at] != 0: at = (at+1) and (NativeFusionSlotLimit-1)
      map[at] = (uint64(token) shl 32) or uint64(index+1)
    let admitted = flatPlanIdentity(f.plan)
    for index in 0..<admitted.jumps.len:
      let target = admitted.jumps[index]
      if not target.valid or target.pc == high(uint32): continue
      let token = target.pc+1
      var at = nativeFusionSlot(token)
      for probe in 0..<map.len:
        let value = map[at]
        if value == 0: break
        if uint32(value shr 32) == token:
          blocks[int(uint32(value and 0xffffffff'u64)-1)].indirectEntry = true
          break
        at = (at+1) and (NativeFusionSlotLimit-1)
    true

  proc reserveFlatFusionSuccessors(f: FlatFrame, blocks: var seq[NativeFusionBlock], cap: int,
      hasIndirect: var bool) =
    ## Try each pinned unconditional edge in rank order, then extend through admitted successors.
    ## Reconstruct each reached header at most once here, even if several edges share the same
    ## refused successor. Each anchor and walked edge uses at most one slot, so fewer than
    ## twice the graph limit fit in the fixed map.
    var seen = default(array[NativeFusionSlotLimit, uint32])
    template slotFor(key: uint32): int =
      ## Find the existing key or next empty bucket in the bounded cold walk.
      block:
        var slot = nativeFusionSlot(key)
        while seen[slot] != 0 and seen[slot] != key:
          slot = (slot+1) and (NativeFusionSlotLimit-1)
        slot
    for item in blocks:
      let token = item.header+1
      seen[slotFor(token)] = token
    var index = 0
    while index < blocks.len and blocks.len < cap:
      let target = blocks[index].targets[0]
      if target != NativeEntryFailure and blocks[index].targets[1] == NativeEntryFailure:
        # Binding proved this is a resolved original single-target branch.
        let token = target+1
        let slot = slotFor(token)
        if seen[slot] == 0:
          seen[slot] = token
          var successor = default(NativeFusionBlock)
          if bindFlatFusion(f, target, successor):
            hasIndirect = hasIndirect or successor.indirect
            blocks.add(successor)
      inc index

  proc selectFlatFusion(f: FlatFrame, probe: FlatFusionProbe): seq[NativeFusionBlock] =
    ## Reuse ranks anchor the graph. In a full ranking, reserve one eighth of its slots
    ## to keep hot paths native through complete successors that sparse sampling can miss.
    ## A refused successor leaves the slot available to the original rank order.
    if probe.taken < 4096 or f.preparationFailure != FlatError.None: return @[]
    var rank = default(array[1024, uint16])
    var count = 0
    for slot in 0..<probe.samples.len:
      if probe.samples[slot].count < 4: continue
      var at = count
      let score = probe.samples[slot].count
      while at > 0 and probe.samples[int(rank[at-1])].count < score:
        rank[at] = rank[at-1]
        dec at
      rank[at] = uint16(slot)
      inc count
    if count < 2: return @[]
    let cap = min(count, NativeFusionBlockLimit)
    var requested = newSeqOfCap[NativeFusionBlock](cap)
    if requested.rawData == nil: return @[]
    let anchors = if cap == NativeFusionBlockLimit: cap-cap div 8 else: cap
    var hasIndirect = false
    template appendRanked(token: uint32) =
      ## Bind the sampled header before granting it a graph slot.
      if token != 0:
        var item = default(NativeFusionBlock)
        if bindFlatFusion(f, token-1, item):
          hasIndirect = hasIndirect or item.indirect
          requested.add(item)
    var index = 0
    while index < count and requested.len < anchors:
      let token = probe.samples[int(rank[index])].token
      appendRanked(token)
      inc index
    if requested.len == anchors and anchors < cap:
      reserveFlatFusionSuccessors(f, requested, cap, hasIndirect)
      let reservedEnd = requested.len
      while index < count and requested.len < cap:
        # Only the reserved tail can duplicate a remaining sample.
        let token = probe.samples[int(rank[index])].token
        var included = false
        for other in anchors..<reservedEnd:
          if requested[other].header+1 == token:
            included = true
            break
        if not included: appendRanked(token)
        inc index
    if requested.len < 2: return @[]
    if hasIndirect:
      # Static-only candidates need neither a temporary target map nor a scan of the original table.
      if not markFlatIndirectEntries(f, requested): return @[]
    requested

  proc offerFlatFusion(f: FlatFrame, probe: FlatFusionProbe) =
    ## Publish only the complete checked graph selected from this frame.
    var requested = selectFlatFusion(f, probe)
    if requested.len >= 2:
      discard offerNativeFusion(f.nativeSession, requested)

  proc flatFusionEntry(f: var FlatFrame, off: uint32): uint32 =
    ## Validate exact debits and the source path before publishing any result.
    let graph = f.fusionBlocks
    let image = f.fusionImage
    if graph == nil or image == nil or f.info.blockCharged or f.barrier != flatStop:
      return flatCharge(f, off)
    let slots = f.fusionSlots
    let context = f.fusionContext
    let receipts = f.fusionReceipts
    if slots == nil or context == nil or receipts == nil:
      return flatLocal(f, off, oracle.StepError.BackendFailure)
    let token = off+1
    var at = nativeFusionSlot(token)
    var slot = -1
    for probe in 0..<slots[].len:
      let value = slots[][at]
      if value.token == token:
        slot = int(value.index)
        break
      if value.token == 0: break
      at = (at+1) and (NativeFusionSlotLimit-1)
    if slot < 0: return flatLocal(f, off, oracle.StepError.BackendFailure)
    let gas = uint64(f.info.gas)
    let quota = f.remaining
    context[].gas = gas
    context[].remaining = quota
    let next = enterNativeFusion(image[], slot, f.info.registers, context[])
    if next >= uint32(f.handlers.len): return flatLocal(f, off, oracle.StepError.BackendFailure)
    let receipt = if nativeFusionCycleEntry(image[], slot):
      nativeFusionCycleExit(graph[], uint32(slot+1), next, gas, quota, context[])
    else: checkNativeFusionExit(receipts[], graph[], off, next, gas, quota, context[])
    if not receipt.valid: return flatLocal(f, off, oracle.StepError.BackendFailure)
    # The validated receipt carries the last source identity; zero names only an empty unpaid return.
    let lastToken = receipt.lastToken
    if lastToken == 0: return flatCharge(f, off)
    if uint64(lastToken) > uint64(graph[].len):
      return flatLocal(f, off, oracle.StepError.BackendFailure)
    let last {.cursor.} = graph[][int(lastToken-1)]
    if receipt.paidHeader == 0 and last.indirect:
      # Recheck the final cache grant and pre-write address even when a path proof is cached.
      let address = context[].address
      let jumps = context[].jumps
      if jumps == nil or address == 0 or address > 0xffffffff'u64 or
          address == 0xffff0000'u64 or (address and 1) != 0:
        return flatLocal(f, off, oracle.StepError.BackendFailure)
      let tag = jumps[][dynamicJumpSlot((address shr 1)-1)]
      if (tag shr 32) != (address shr 1) or uint32(tag and 0xffffffff'u64) != next+1:
        return flatLocal(f, off, oracle.StepError.BackendFailure)
      let branch = last.branch
      let base = if branch.opcode == 50: branch.slots.aIndex else: branch.slots.bIndex
      if branch.opcode == 50 or branch.slots.aIndex != branch.slots.bIndex:
        if ((uint64(f.info.registers[base])+uint64(last.indirectDelta)) and 0xffffffff'u64) != address:
          return flatLocal(f, off, oracle.StepError.BackendFailure)
      if branch.opcode == 180 and uint64(f.info.registers[branch.slots.aIndex]) !=
          last.indirectValue:
        return flatLocal(f, off, oracle.StepError.BackendFailure)
    elif receipt.paidHeader == 0 and last.targets[1] != NativeEntryFailure:
      let op = last.branch
      let taken = branchConditionOperands[-1](op.slots, op.immediate, op.opcode, f.info.registers)
      if next != last.targets[int(taken)]: return flatLocal(f, off, oracle.StepError.BackendFailure)
    f.info.gas = MachineGas(context[].gas)
    f.remaining = context[].remaining
    f.info.blockCharged = receipt.paidHeader != 0
    var operations = uint64(receipt.attempted)
    if receipt.paidHeader != 0:
      let header = receipt.paidHeader-1
      let source = f.sites[int(next)]
      if source < last.first or source-last.first >= last.span:
        return flatLocal(f, off, oracle.StepError.BackendFailure)
      f.reservation = header or flatReservationHeaderFlag
      operations -= uint64(last.span-(source-last.first))
    else:
      f.reservation = 0
    if operations != 0:
      recordNativeMixedLoop(f.nativeSession, operations, false, receipt.branches)
    next
