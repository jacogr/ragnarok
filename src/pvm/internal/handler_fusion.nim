# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included by the exclusive handler stream. An observed header only ranks a candidate.
## The copied block must reproduce original operands, paid extent and positive static edges.
## The primary retains its handlers. Fusion patches only disjoint ordinary headers during
## one segment and restores all of them before releasing the auxiliary arena.

when declared(FlatFrame):
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

  proc bindFlatFusion(f: FlatFrame, off: uint32, item: var NativeFusionBlock): bool =
    ## Decode the sealed source once during selection. A refused block stays checked.
    if uint64(off) >= uint64(f.handlers.len) or uint64(off) >= uint64(f.sites.len) or
        f.handlers[int(off)] != flatCharge: return false
    let ordinal = f.sites[int(off)]
    if uint64(ordinal) >= uint64(f.plan.facts.len): return false
    let pc = f.plan.facts[int(ordinal)].pc
    var header = 0'u32
    var source = default(FlatSourceInterval)
    var summary = default(FlatSourceSummary)
    if not flatCompleteOriginalHeader(f, pc, NativeReadFactLimit, header, source): return false
    if header != off or not flatWalkCompleteSource(f, header, source, summary): return false
    if nativeReadObservationOverlaps(f.nativeSession, NativeReadBodyInfo(header: off,
        terminal: summary.terminal, first: source.first, last: source.last,
        epoch: nativeEpoch(f.nativeSession))): return false
    let price = blockGas(f.plan.source, CodeAddress(uint64(pc)), f.plan.cycles)
    if price.error != GasError.None or uint64(price.value) != source.price: return false
    item = NativeFusionBlock(header: off, terminal: summary.terminal, first: source.first,
      span: source.span, price: source.price, targets: [NativeEntryFailure, NativeEntryFailure])
    let priceIndex = f.plan.facts[int(source.first)].priceIndex
    var node = off+1
    for index in source.first..source.last:
      let fact = f.plan.facts[int(index)]
      if fact.priceIndex != priceIndex: return false
      if fact.opcode == 2: continue
      let decoded = instruction(f.plan.source, CodeAddress(uint64(fact.pc)))
      if decoded.error != ProgramError.None: return false
      let original = decoded.value
      if original.opcode != fact.opcode or
          uint64(original.address)+1+uint64(original.skip) != uint64(fact.next): return false
      let payload = flatSourcePayload(decoded)
      let args = f.arguments[int(node)]
      let worker = f.handlers[int(node)]
      if node != summary.terminal:
        if args != payload.args: return false
        if worker != payload.handler:
          # Fused scalar and chained memory handlers retain original individual sites.
          let paired = if isRegisterOpcode(fact.opcode): flatRegisterPairHandler(fact.opcode)
            else: flatMemoryPairHandler(fact.opcode)
          if paired == nil or worker != paired:
            if index >= source.last or node+1 >= summary.terminal or
                f.sites[int(node+1)] != index+1: return false
            let fused = flatFusedRegisterHandler(fact.opcode, f.plan.facts[int(index+1)].opcode)
            if fused == nil or worker != fused: return false
        let slot = int(node-off-1)
        if slot >= item.operations.len: return false
        let op = fact.opcode
        if nativeMixedLoopStoreWidth(op) != 0 or nativeReadOpcode(nativeReadEncodingOpcode(op)):
          item.guards = item.guards or (1'u32 shl slot)
        elif not supportedScalarOpcode(op): return false
        item.operations[slot] = NativeOperation(opcode: op, slots: args.slots, immediate: args.x)
      elif fact.opcode in [1'u8, 40]:
        # The sealed original destination proves the edge once the cached operand
        # is a positive node for that exact original source. Unresolved workers
        # still carry a guest PC. Their identity must be excluded.
        if worker != payload.handler and flatSourceHeader(f, args.y, payload.args.y):
          item.targets[0] = args.y
          item.branch = NativeOperation(opcode: fact.opcode)
      elif fact.opcode == 80:
        # Link the cached edge only if its register and immediate match the original write.
        if worker == flatCachedJump[80] and flatSourceHeader(f, args.y, payload.args.y):
          if args.slots != payload.args.slots or args.x != payload.args.x: return false
          item.targets[0] = args.y
          item.branch = NativeOperation(opcode: 80, slots: payload.args.slots,
            immediate: payload.args.x)
      else:
        let cached = fusionBranchHandler(fact.opcode)
        if cached != nil and worker == cached:
          let yes = uint32(args.x shr 32)
          let no = args.y
          let mask = 0xffffffff'u64
          if args.slots != payload.args.slots or (args.x and mask) != (payload.args.x and mask) or
              not flatSourceHeader(f, yes, uint32(payload.args.x shr 32)) or
              not flatSourceHeader(f, no, payload.args.y): return false
          item.targets = [no, yes]
          item.branch = NativeOperation(opcode: fact.opcode, slots: args.slots,
            immediate: flatSext32(uint32(args.x and mask)))
      inc node
    item.complete

  proc sampleFlatFusion(probe: var FlatFusionProbe, header: uint32) {.noinline.} =
    ## Sparse bounded counts. The pseudorandom interval avoids lockstep with guest loops.
    var seed = probe.seed
    seed = seed xor (seed shl 13)
    seed = seed xor (seed shr 17)
    seed = seed xor (seed shl 5)
    probe.seed = seed
    probe.down = 1+(seed and 63)
    if probe.taken == 262144'u32: return
    inc probe.taken
    if header >= NativeEntryLimit: return
    let token = header+1
    let start = (token*0x9e3779b9'u32) shr 22
    for index in 0'u32..3'u32:
      let slot = int((start+index) and 1023)
      if probe.samples[slot].token in [0'u32, token]:
        probe.samples[slot].token = token
        inc probe.samples[slot].count
        return

  proc observeFlatFusion(probe: var FlatFusionProbe, header: uint32) {.inline.} =
    ## Keep the ordinary dispatcher free of sampling state outside the training segment.
    if probe.taken < 262144'u32:
      dec probe.down
      if probe.down == 0: sampleFlatFusion(probe, header)

  proc offerFlatFusion(f: FlatFrame, probe: FlatFusionProbe) =
    ## Rank at most the fixed sample table. Only candidates with real observed reuse
    ## pay for source reconstruction. Do not allocate by source size.
    if probe.taken < 4096 or f.preparationFailure != FlatError.None: return
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
    if count < 2: return
    let cap = min(count, NativeFusionBlockLimit)
    var requested = newSeqOfCap[NativeFusionBlock](cap)
    if requested.rawData == nil: return
    for index in 0..<count:
      if requested.len == cap: break
      let token = probe.samples[int(rank[index])].token
      var item = default(NativeFusionBlock)
      if bindFlatFusion(f, token-1, item): requested.add(item)
    if requested.len < 2: return
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
    var at = int((token*0x9e3779b9'u32) shr 24)
    var slot = -1
    for probe in 0..<slots[].len:
      let value = slots[][at]
      if value.token == token:
        slot = int(value.index)
        break
      if value.token == 0: break
      at = (at+1) and 255
    if slot < 0: return flatLocal(f, off, oracle.StepError.BackendFailure)
    let gas = uint64(f.info.gas)
    let quota = f.remaining
    context[].gas = gas
    context[].remaining = quota
    let next = enterNativeFusion(image[], slot, f.info.registers, context[])
    if next >= uint32(f.handlers.len): return flatLocal(f, off, oracle.StepError.BackendFailure)
    let receipt = checkNativeFusionExit(receipts[], graph[], off, next, gas, quota, context[])
    if not receipt.valid: return flatLocal(f, off, oracle.StepError.BackendFailure)
    # The validated receipt carries the last source identity; zero names only an empty unpaid return.
    let lastToken = receipt.lastToken
    if lastToken == 0: return flatCharge(f, off)
    if uint64(lastToken) > uint64(graph[].len):
      return flatLocal(f, off, oracle.StepError.BackendFailure)
    let last {.cursor.} = graph[][int(lastToken-1)]
    if receipt.paidHeader == 0 and last.targets[1] != NativeEntryFailure:
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
