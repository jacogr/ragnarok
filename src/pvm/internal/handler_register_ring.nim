# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind copied register-loop certificates to their original checked stream.

when declared(FlatFrame):
  when NativeCheckedReadEnabled and defined(pvmX86Jit):
    proc flatNativeAdjacent[First: static[bool]](f: var FlatFrame, off: uint32): uint32

  proc flatRingHeaderMatches(f: FlatFrame, header, terminal: uint32, index, count: int): bool =
    ## Only the actual charged handlers and their positively linked terminal branches are eligible.
    let charged = f.handlers[int(header)]
    let ending = f.handlers[int(terminal)]
    when NativeCheckedReadEnabled and defined(pvmX86Jit):
      if count == 2:
        if index == 0:
          return ending == flatBranch[170] and (charged == flatChargedAdjacent[true, false] or
            charged == flatChargedAdjacent[true, true] or charged == flatNativeAdjacent[true])
        return ending == flatBranch[81] and (charged == flatChargedAdjacent[false, false] or
          charged == flatChargedAdjacent[false, true] or charged == flatNativeAdjacent[false])
    case index
    of 0:
      ending == flatBranch[82] and (charged == flatChargedShape[200, 139, 82, true] or
        charged == flatChargedShape[200, 139, 82, false])
    of 1:
      ending == flatBranch[88] and (charged == flatChargedShape[131, -1, 88, true] or
        charged == flatChargedShape[131, -1, 88, false])
    else:
      ending == flatBranch[173] and (charged == flatChargedShape[151, 152, 173, true] or
        charged == flatChargedShape[151, 152, 173, false])

  proc flatRingCertificate(f: FlatFrame, headers: openArray[uint32]): NativeRegisterRing =
    ## Copy complete original blocks with no source resolution, pricing or invocation borrows.
    result = default(NativeRegisterRing)
    if f.plan == nil or f.plan.singleStep or f.pricingKind != 0 or
        f.preparationFailure != FlatError.None:
      return
    assert headers.len in 2..3
    const spans = [3'u32, 2, 3]
    var ring = default(NativeRegisterRing)
    for index in 0..<headers.len:
      let header = headers[index]
      let span = spans[index]
      if header >= NativeEntryLimit: return
      let terminal = header+span
      if uint64(terminal) >= uint64(f.handlers.len) or
          uint64(terminal) >= uint64(f.arguments.len) or uint64(terminal) >= uint64(f.sites.len):
        return
      if not flatRingHeaderMatches(f, header, terminal, index, headers.len): return
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

  proc flatSelectRingHandlers[Ring: static[bool]](f: var FlatFrame, headers: array[3, uint32]) =
    ## Swap only the three certified headers after a complete checked round or ready revalidation.
    let a: FlatHandler = flatChargedShape[200, 139, 82, Ring]
    let b: FlatHandler = flatChargedShape[131, -1, 88, Ring]
    let c: FlatHandler = flatChargedShape[151, 152, 173, Ring]
    when Ring:
      flatInstallNativePatch(f, headers[0], a)
      flatInstallNativePatch(f, headers[1], b)
      flatInstallNativePatch(f, headers[2], c)
    else:
      # Cold nomination changes only checked shape routing; no image owns these handlers.
      f.handlers[int(headers[0])] = a
      f.handlers[int(headers[1])] = b
      f.handlers[int(headers[2])] = c

  proc flatObserveNativeRing(f: var FlatFrame, first, middle, last: uint32): bool {.noinline.} =
    ## Nominate a checked round once, then dispatch the stock checked worker until publication.
    let epoch = nativeRingAdmissionEpoch(f.nativeSession)
    if epoch == 0: return false
    let headers = [first, middle, last]
    let ring = flatRingCertificate(f, headers)
    if not ring.complete: return false
    nominateNativeRing(f.nativeSession, ring, epoch)
    flatSelectRingHandlers[false](f, headers)
    true

  when NativeCheckedReadEnabled and defined(pvmX86Jit):
    proc flatObserveNativeAdjacent(f: var FlatFrame, first, second: uint32) {.noinline.} =
      ## One closed checked round can nominate an x86 pair without creating or publishing code.
      let epoch = nativeRingAdmissionEpoch(f.nativeSession)
      if epoch == 0: return
      let ring = flatRingCertificate(f, [first, second])
      if not ring.complete: return
      nominateNativeRing(f.nativeSession, ring, epoch)
      # Further checked visits use the normal workers while this candidate owns the nomination.
      f.handlers[int(first)] = flatChargedAdjacent[true, false]
      f.handlers[int(second)] = flatChargedAdjacent[false, false]

    proc flatNativeAdjacent[First: static[bool]](f: var FlatFrame, off: uint32): uint32 =
      ## Only the installed image may consume a whole unpaid block; all other states stay checked.
      var destination = flatStop
      if flatTryNativeRing(f, off, destination): return destination
      flatChargedAdjacent[First, false](f, off)

  proc flatInstallNativeRing(f: var FlatFrame, ring: NativeRegisterRing) =
    ## Compare every source and pricing fact after restoring the same exclusive stream.
    let headers = [ring.blocks[0].header, ring.blocks[1].header, ring.blocks[2].header]
    let count = nativeRingBlockCount(ring)
    if flatRingCertificate(f, headers.toOpenArray(0, count-1)) != ring:
      invalidateNativeStream(f.nativeSession)
      return
    when NativeCheckedReadEnabled and defined(pvmX86Jit):
      if count == 2:
        flatInstallNativePatch(f, headers[0], flatNativeAdjacent[true])
        flatInstallNativePatch(f, headers[1], flatNativeAdjacent[false])
        f.nativeRingInstalled = true
        return
    flatSelectRingHandlers[true](f, headers)
    f.nativeRingInstalled = true

  proc flatTryNativeRing(f: var FlatFrame, header: uint32, destination: var uint32): bool =
    ## A full unpaid entry may run natively. The original header handles partial, paid and gas stops.
    if f.info.blockCharged or f.barrier != flatStop or f.pricingKind != 0 or
        not matchesNativeImage(f.nativeSession, f.nativeInstallation.key, NativeKind.RegisterRing):
      return false
    let charge = f.arguments[int(header)]
    if f.remaining < uint64(charge.y) or uint64(f.info.gas) < charge.x: return false
    let rotation = nativeRingRotation(f.nativeSession, header)
    if rotation > 2: return false
    var context = NativeRingContext(gas: uint64(f.info.gas), remaining: f.remaining,
        entry: rotation)
    destination = runNativeRing(f.nativeSession, f.info.registers, context)
    f.info.gas = MachineGas(context.gas)
    f.remaining = context.remaining
    f.info.blockCharged = false
    f.reservation = 0 # A completed native branch leaves no checked reservation to refund.
    true
