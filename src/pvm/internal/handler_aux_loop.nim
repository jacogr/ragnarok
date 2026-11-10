# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Seal a checked byte-store loop and run bounded visits against frame-owned memory.

when declared(FlatFrame):
  const
    AuxNoPage = high(uint32) ## Guest pages occupy only the low 20 bits.
    AuxWarmBackedges = uint32((NativeInvocationFloor+AuxVisitSpan-1) div AuxVisitSpan)
    AuxColdProbeLimit = 8'u8 ## At most this many complete cold proofs per source epoch.

  type AuxRefusal {.pure.} = enum
    ## The original checked header owns all fallbacks.
    None, Paid, Budget, Gas, Read, Writable, Dirty

  proc buildFlatAuxProof(f: FlatFrame, pc: uint32): AuxProof =
    ## Bind every original source operation, already cached arm and original price.
    result = default(AuxProof)
    if f.plan == nil or f.plan.allowNative or f.plan.singleStep or f.pricingKind != 0 or
        f.preparationFailure != FlatError.None: return
    var header = 0'u32
    var source = default(FlatSourceInterval)
    var summary = default(FlatSourceSummary)
    if not flatCompleteOriginalHeader(f, pc, uint32(AuxVisitSpan), header, source) or
        source.span != uint32(AuxVisitSpan) or f.handlers[int(header)] != flatCharge or
        not flatWalkCompleteSource(f, header, source, summary) or
        summary.operations != uint32(AuxVisitSpan): return
    let branch: FlatHandler = flatBranch[171]
    if f.handlers[int(summary.terminal)] != branch: return
    let priceIndex = f.plan.facts[int(source.first)].priceIndex
    for index, opcode in AuxOps:
      # Shape misses stop before price computation and operand decoding.
      let fact = f.plan.facts[int(source.first)+index]
      if fact.opcode != opcode or fact.priceIndex != priceIndex: return
    let price = blockGas(f.plan.source, CodeAddress(uint64(pc)), f.plan.cycles)
    if price.error != GasError.None or uint64(price.value) != source.price: return
    var proof = AuxProof(read: initNativeAuxReadPrefix(header, source.first,
      nativeEpoch(f.nativeSession)), price: source.price)
    for index in 0..<AuxOps.len:
      let ordinal = source.first+uint32(index)
      let fact = f.plan.facts[int(ordinal)]
      let node = header+1+uint32(index)
      let original = flatSourcePayload(f.plan, fact)
      let payload = original.args
      let actual = f.arguments[int(node)]
      if actual.slots != payload.slots: return
      let op = NativeOperation(opcode: fact.opcode, slots: payload.slots, immediate: payload.x)
      if index < AuxOps.len-1:
        if actual.x != payload.x or actual.y != payload.y: return
        let worker = f.handlers[int(node)]
        if worker != original.handler:
          let paired = if isRegisterOpcode(fact.opcode): flatRegisterPairHandler(fact.opcode)
            else: flatMemoryPairHandler(fact.opcode)
          if paired == nil or worker != paired: return
      if index < 11:
        if not addReadBodyOperation(proof.read, node, ordinal, op): return
      elif index == 11:
        proof.store = op
      elif index < AuxOps.len-1:
        proof.suffix[index-12] = op
      else:
        var exitSource = default(FlatSourceInterval)
        if uint32(payload.x shr 32) != pc or uint32(actual.x shr 32) != header or
            uint32(actual.x and 0xffffffff'u64) != uint32(payload.x and 0xffffffff'u64) or
            not flatCompleteOriginalHeader(f, payload.y, high(uint32),
              proof.exitHeader, exitSource) or actual.y != proof.exitHeader or
            proof.exitHeader == header: return
        proof.branch = op.slots
    if proof.read.complete: result = proof

  proc observeFlatAuxSource(f: var FlatFrame, pc, header, terminal: uint32) =
    ## Inspect one already-cached backedge and keep the first qualifying interval per epoch.
    if f.plan.allowNative or f.pricingKind != 0 or
        f.arguments[int(header)].y != uint32(AuxVisitSpan):
      return
    let first = f.sites[int(header)]
    if int(first) >= f.plan.facts.len or f.plan.facts[int(first)].opcode != AuxOps[0]:
      return
    let epoch = auxObservationEpoch(f.nativeSession)
    if epoch == 0: return
    if f.auxSource.epoch != epoch:
      f.auxSource = FlatAuxSource(epoch: epoch)
    if f.auxSource.headerToken != 0 or f.auxSource.coldChecks >= AuxColdProbeLimit:
      return
    inc f.auxSource.coldChecks
    let proof = buildFlatAuxProof(f, pc)
    if proof.read.complete and proof.read.info.header == header and
        header+uint32(AuxVisitSpan) == terminal:
      f.auxSource.pc = pc
      f.auxSource.headerToken = header+1

  func flatAuxSourceCurrent(f: FlatFrame): bool =
    ## Skip all proof work when the exact stream has no current source nomination.
    f.auxSource.headerToken != 0 and f.auxSource.epoch == nativeEpoch(f.nativeSession)

  proc auxStoreGuard(f: FlatFrame, address: uint64, verifiedPage: var uint32): AuxRefusal =
    ## Both dirty representations already own the target page. Refuse clean writes
    ## before any data mutation so the original store installs exact membership.
    if address < 65536 or address >= uint64(high(uint32)): return AuxRefusal.Writable
    let covered = if address >= f.stackBase:
      address-f.stackBase < uint64(f.stack.len)
    elif address >= f.rwBase:
      address-f.rwBase < uint64(f.rw.len)
    else:
      false
    if not covered: return AuxRefusal.Writable
    let page = uint32(address shr 12)
    let word = int(page shr 6)
    if word >= f.dirtyPages.len or
        (f.dirtyPages[word] and (1'u64 shl int(page and 63))) == 0:
      return AuxRefusal.Dirty
    if page == verifiedPage: return AuxRefusal.None
    for entry in f.dirtyIndices:
      if entry == page:
        verifiedPage = page
        return AuxRefusal.None
    AuxRefusal.Dirty

  proc runFlatAuxChunk(f: var FlatFrame, proof: AuxProof, image: NativeImage,
      refusal: var AuxRefusal): uint32 =
    ## Resume the first uncommitted header on every refusal. A successful prefix
    ## publishes source gas, attempts, registers and its byte once per visit.
    let header = proof.read.info.header
    result = header
    refusal = AuxRefusal.None
    if f.info.blockCharged or f.barrier != flatStop:
      refusal = AuxRefusal.Paid
      return
    if not f.readContextReady: prepareFlatReadContext(f)
    # The exclusive frame cannot invoke a callback or reset its dirty list inside this chunk.
    # The only store has a set bitmap bit, so the checked worker leaves list membership alone.
    var verifiedPage = AuxNoPage
    for _ in 0..<AuxMaxVisits:
      if f.remaining == 0:
        refusal = AuxRefusal.Budget
        return
      if uint64(f.info.gas) < proof.price:
        refusal = AuxRefusal.Gas
        return
      if f.remaining < AuxVisitSpan:
        refusal = AuxRefusal.Budget
        return
      var stage = default(AuxStage)
      if not stageAuxVisit(image, proof, f.info.registers, f.readContext, stage):
        refusal = AuxRefusal.Read
        return
      refusal = auxStoreGuard(f, stage.address, verifiedPage)
      if refusal != AuxRefusal.None: return
      if not flatStore[1](f, header+12, stage.address, stage.value):
        abortNativeReceipt()
      f.info.registers = stage.registers
      f.info.gas = MachineGas(uint64(f.info.gas)-proof.price)
      f.remaining -= AuxVisitSpan
      f.reservation = header or flatReservationHeaderFlag
      result = stage.next
      if result != header: return
