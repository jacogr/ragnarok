# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind and run the bitmap scan through original paid blocks and checked unpaid side exits.

when declared(FlatFrame):
  proc flatBitmapCertificate(f: FlatFrame, root: uint32, epoch: uint64): NativeBitmapLoop =
    ## Follow cached edges and compare every copied operand with the original marked program.
    result = default(NativeBitmapLoop)
    if epoch == 0 or f.plan == nil or f.plan.singleStep or f.pricingKind != 0 or
        f.preparationFailure != FlatError.None: return
    var proof = NativeBitmapLoop(epoch: epoch)
    var header = root
    var operation = 0
    for role in BitmapBlock:
      let span = uint32(BitmapSpans[ord(role)])
      if header >= NativeEntryLimit or int(header) >= f.sites.len: return
      let first = f.sites[int(header)]
      if int(first) >= f.plan.facts.len: return
      let pc = f.plan.facts[int(first)].pc
      var resolved = 0'u32
      var source = default(FlatSourceInterval)
      if not flatCompleteOriginalHeader(f, pc, span, resolved, source) or resolved != header or
          source.span != span or source.price == 0: return
      let charge = f.handlers[int(header)]
      if charge != flatCharge:
        let original = case role
          of BitmapBlock.Advance:
            charge == flatChargedAdjacent[true]
          of BitmapBlock.Parity:
            charge == flatChargedAdjacent[false]
          else: false
        if not original: return
      var walk = default(FlatSourceSummary)
      if not flatWalkCompleteSource(f, header, source, walk) or walk.operations != span: return
      let priceIndex = f.plan.facts[int(first)].priceIndex
      proof.sites[role] = NativeBitmapSite(header: header, first: first, price: source.price)
      for i in 0..<int(span):
        let fact = f.plan.facts[int(first)+i]
        let node = int(header)+i+1
        if fact.opcode != BitmapOpcodes[operation] or fact.priceIndex != priceIndex or
            f.sites[node] != first+uint32(i): return
        let original = flatSourcePayload(f.plan, fact)
        let cached = f.arguments[node]
        if cached.slots != original.args.slots: return
        var immediate = original.args.x
        if i+1 < int(span):
          # Original body nodes may be fused by the checked engine, but their operands stay sealed.
          if cached.x != original.args.x or cached.y != original.args.y: return
        elif role == BitmapBlock.Read:
          if f.handlers[node] != flatCachedJump[40] or cached.x != original.args.x or
              cached.y != root or not flatSourceHeader(f, root, original.args.y): return
          immediate = 0
        else:
          let branch = f.handlers[node]
          let matches = case role
            of BitmapBlock.Advance: branch == flatBranch[170]
            of BitmapBlock.Parity: branch == flatBranch[81]
            else: branch == flatBranch[174]
          if not matches or
              uint32(cached.x and 0xffffffff'u64) != uint32(original.args.x and 0xffffffff'u64):
            return
          let yes = uint32(cached.x shr 32)
          if not flatSourceHeader(f, yes, uint32(original.args.x shr 32)) or
              not flatSourceHeader(f, cached.y, original.args.y): return
          case role
          of BitmapBlock.Advance: proof.exits[BitmapExit.End] = yes
          of BitmapBlock.Parity:
            if yes != root: return
          of BitmapBlock.Midpoint: proof.exits[BitmapExit.Reset] = yes
          of BitmapBlock.Index: proof.exits[BitmapExit.Trap] = yes
          else: discard
          header = cached.y
          immediate = flatSext32(uint32(original.args.x and 0xffffffff'u64))
        proof.operations[operation] = NativeOperation(opcode: fact.opcode,
          slots: original.args.slots, immediate: immediate)
        inc operation
    if proof.complete: result = proof

  proc observeFlatBitmap(f: var FlatFrame, root: uint32) =
    ## Settled execution can prove branches first reached through a suffix on the cold trip.
    let epoch = bitmapAdmissionEpoch(f.nativeSession)
    if epoch == 0: return
    let proof = flatBitmapCertificate(f, root, epoch)
    if proof.epoch != 0: nominateNativeBitmap(f.nativeSession, proof)

  proc flatNativeBitmap(f: var FlatFrame, off: uint32): uint32 =
    ## A refused Read returns its original header with gas, attempts and guest registers
    ## as they were before that block. Checked execution then charges and runs that block.
    ## At Advance, call the saved charge worker directly to avoid reentering native.
    let original = f.nativeOriginal
    if original == nil or off != f.nativeEntry:
      return flatLocal(f, off, oracle.StepError.BackendFailure)
    if f.pricingKind != 0 or f.info.blockCharged or f.barrier != flatStop or
        not matchesNativeImage(f.nativeSession, f.nativeInstallation.key, NativeKind.BitmapLoop):
      return original(f, off)
    # Intersect the private RW borrow with the scalar fast-path range. Other bytes stay checked.
    let base = max(f.rwBase, 65536'u64)
    var context = NativeBitmapContext(gas: uint64(f.info.gas), remaining: f.remaining,
      last: BitmapNoCompleted, base: base)
    if base < 0xffffffff'u64 and base-f.rwBase < uint64(f.rw.len):
      let skip = int(base-f.rwBase)
      context.length = min(uint64(f.rw.len-skip), 0xffffffff'u64-base)
      context.bytes = f.rw.borrowedData(skip)
    let next = runNativeBitmap(f.nativeSession, f.nativeInstallation.key, f.info.registers, context)
    if next == NativeEntryFailure: return flatLocal(f, off, oracle.StepError.BackendFailure)
    f.info.gas = MachineGas(context.gas)
    f.remaining = context.remaining
    f.reservation = 0
    if next == off: return original(f, off)
    next

  proc installFlatBitmap(f: var FlatFrame, proof: NativeBitmapLoop) =
    ## Rebind the exact worker proof before changing one original unpaid entry.
    let root = proof.sites[BitmapBlock.Advance].header
    if flatBitmapCertificate(f, root, proof.epoch) != proof:
      invalidateNativeStream(f.nativeSession)
      return
    f.nativeOriginal = f.handlers[int(root)]
    f.nativeEntry = root
    f.nativeInstalledEpoch = proof.epoch
    flatInstallNativePatch(f, root, flatNativeBitmap)
