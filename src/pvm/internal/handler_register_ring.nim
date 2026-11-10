# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact checked stream binding for a copied three-header register-loop certificate.

when declared(FlatFrame):
  proc flatRingCertificate(f: FlatFrame, headers: array[3, uint32]): NativeRegisterRing =
    ## Copy complete original blocks with no source resolution, pricing or invocation borrows.
    result = default(NativeRegisterRing)
    if f.plan == nil or f.plan.singleStep or f.pricingKind != 0 or
        f.preparationFailure != FlatError.None:
      return
    let shapeA: FlatHandler = flatChargedShape[200, 139, 82]
    let shapeB: FlatHandler = flatChargedShape[131, -1, 88]
    let shapeC: FlatHandler = flatChargedShape[151, 152, 173]
    let branchA: FlatHandler = flatBranch[82]
    let branchB: FlatHandler = flatBranch[88]
    let branchC: FlatHandler = flatBranch[173]
    const spans = [3'u32, 2, 3]
    var ring = default(NativeRegisterRing)
    for index in 0..2:
      let header = headers[index]
      let span = spans[index]
      if header >= NativeEntryLimit: return
      let terminal = header+span
      if uint64(terminal) >= uint64(f.handlers.len) or
          uint64(terminal) >= uint64(f.arguments.len) or uint64(terminal) >= uint64(f.sites.len):
        return
      let charged = f.handlers[int(header)]
      let ending = f.handlers[int(terminal)]
      if index == 0:
        if charged != shapeA or ending != branchA: return
      elif index == 1:
        if charged != shapeB or ending != branchB: return
      else:
        if charged != shapeC or ending != branchC: return
      let first = f.sites[int(header)]
      if uint64(first)+uint64(span) > uint64(f.plan.facts.len): return
      let root = f.plan.facts[int(first)]
      let charge = f.arguments[int(header)]
      if charge.y != span or root.sourceCount != span or not flatSourceHeader(f, header, root.pc):
        return
      var item = NativeRingBlock(header: header, first: first, span: span, price: charge.x)
      for position in 0..<int(span):
        let node = int(header)+position+1
        let ordinal = first+uint32(position)
        let fact = f.plan.facts[int(ordinal)]
        if f.sites[node] != ordinal or fact.priceIndex != root.priceIndex: return
        let original = flatSourcePayload(f.plan, fact)
        let cached = f.arguments[node]
        if cached.slots != original.args.slots: return
        if position == int(span)-1:
          # Positive cached branch identities and both original target PCs prove exact checked edges.
          if not fact.ending or (cached.x and 0xffffffff'u64) != (original.args.x and
              0xffffffff'u64): return
          let yes = uint32(cached.x shr 32)
          let no = cached.y
          if not flatSourceHeader(f, yes, uint32(original.args.x shr 32)) or
              not flatSourceHeader(f, no, original.args.y): return
          let immediate = if fact.opcode <= 90: flatSext32(uint32(cached.x and 0xffffffff'u64))
            else: 0'u64
          item.yes = yes
          item.no = no
          item.branch = NativeOperation(opcode: fact.opcode, slots: cached.slots,
              immediate: immediate)
        else:
          # Every original body instruction has an addressable node before the terminal branch.
          if fact.ending or not fact.fallthrough or cached.x != original.args.x or
              fact.next != f.plan.facts[int(ordinal)+1].pc: return
          item.body[position] = NativeOperation(opcode: fact.opcode, slots: cached.slots,
            immediate: cached.x)
      ring.blocks[index] = item
    if ring.complete: result = ring

  proc flatObserveNativeRing(f: FlatFrame, headers: array[3, uint32]) =
    ## An observed exact closed round can nominate a copied candidate once per epoch.
    let epoch = nativeRingAdmissionEpoch(f.nativeSession)
    if epoch != 0:
      nominateNativeRing(f.nativeSession, flatRingCertificate(f, headers), epoch)

  proc flatInstallNativeRing(f: var FlatFrame, ring: NativeRegisterRing) =
    ## Compare every source and pricing fact after restoring the same exclusive stream.
    let headers = [ring.blocks[0].header, ring.blocks[1].header, ring.blocks[2].header]
    if flatRingCertificate(f, headers) != ring:
      invalidateNativeStream(f.nativeSession)
    else:
      # Keep original handlers installed so the next checked dispatch always owns unpaid fallback.
      f.nativeRingInstalled = true

  proc flatTryNativeRing(f: var FlatFrame, header: uint32, destination: var uint32): bool =
    ## A full unpaid entry may run natively. The original header handles partial, paid and gas stops.
    if f.info.blockCharged or f.barrier != flatStop or f.pricingKind != 0: return false
    let charge = f.arguments[int(header)]
    if f.remaining < uint64(charge.y) or uint64(f.info.gas) < charge.x: return false
    let rotation = nativeRingRotation(f.nativeSession, header)
    if rotation > 2: return false
    var context = NativeRingContext(gas: uint64(f.info.gas), remaining: f.remaining,
        entry: rotation)
    destination = runNativeRing(f.nativeSession, f.info.registers, context)
    f.info.gas = MachineGas(context.gas)
    f.remaining = context.remaining
    f.reservation = 0 # A completed native branch leaves no checked reservation to refund.
    true
