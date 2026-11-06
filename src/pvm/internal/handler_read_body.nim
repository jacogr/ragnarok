# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Checked source certificate and invocation bridge for a bounded native read body.

when declared(FlatFrame):
  func flatReadTerminal(f: FlatFrame, node: uint32, fact: FlatFact): bool =
    ## The original static fallthrough remains checked, whether the stream cached it or not.
    if fact.opcode != 1 or not fact.ending or not fact.fallthrough or
        fact.handler != flatJump[1]: return false
    let target = f.arguments[int(node)].y
    if f.handlers[int(node)] == flatJump[1]: return target == fact.next
    if f.handlers[int(node)] != flatCachedJump[1] or
        int(fact.next) >= f.compiledForPc.len or int(target) >= f.sites.len or
        int(target) >= f.handlers.len or target >= flatReservationHeaderFlag: return false
    let targetFact = f.sites[int(target)]
    int(targetFact) < f.plan.facts.len and f.plan.facts[int(targetFact)].pc == fact.next and
      f.compiledForPc[int(fact.next)] == (target or flatReservationHeaderFlag)+1

  proc buildFlatReadBody(f: FlatFrame, pc: uint32, epoch: uint64): NativeReadBody =
    ## Bind one ordinary complete header, original operations and its unmodified checked terminal.
    result = default(NativeReadBody)
    if f.plan == nil or f.plan.allowNative or f.plan.singleStep or f.pricingKind != 0 or
        f.preparationFailure != FlatError.None: return
    var header = 0'u32
    var source = default(FlatSourceInterval)
    if not flatCompleteOriginalHeader(f, pc, NativeReadFactLimit, header, source): return
    if f.handlers[int(header)] != flatCharge or f.plan.facts[int(source.first)].opcode != 2:
      return
    var walk = default(FlatSourceSummary)
    if not flatWalkCompleteSource(f, header, source, walk) or
        not flatReadTerminal(f, walk.terminal, f.plan.facts[int(source.last)]): return
    var body = initNativeReadBody(header, walk.terminal, source.first, source.last, epoch)
    var ordinal = source.first+1
    var node = header+1
    while ordinal < source.last:
      # The initial noop is the only folded fact this first shape accepts.
      let fact = f.plan.facts[int(ordinal)]
      if fact.opcode == 2 or node >= walk.terminal or f.sites[int(node)] != ordinal or
          fact.priceIndex != f.plan.facts[int(source.first)].priceIndex: return
      let args = f.arguments[int(node)]
      if args.x != fact.args.x or args.y != fact.args.y or args.slots != fact.args.slots: return
      if not addReadBodyOperation(body, node, ordinal, NativeOperation(opcode: fact.opcode,
          slots: fact.args.slots, immediate: fact.args.x)): return
      inc ordinal
      inc node
    if body.complete: result = body

  proc flatNativeReadBody(f: var FlatFrame, off: uint32): uint32 =
    ## Require the exact complete reservation. Refusal replays the original paid body.
    let original = f.nativeOriginal
    assert original != nil and off == f.nativeEntry
    let read = nativeReadInfo(f.nativeSession)
    if read.epoch == 0 or read.epoch != f.nativeInstalledEpoch or off != read.header+1 or
        f.pricingKind != 0 or f.barrier != flatStop or not f.info.blockCharged or
        f.reservation != (read.header or flatReservationHeaderFlag):
      return original(f, off)
    if not f.readContextReady:
      # Fresh frame allocations own these bytes. A replacement frame starts without descriptors.
      f.readContext = [initNativeReadRegion(f.stackBase, f.stack),
        initNativeReadRegion(f.rwBase, f.rw), initNativeReadRegion(f.roBase, f.ro)]
      f.readContextReady = true
    if not runNativeReadBody(f.nativeSession, f.info.registers, f.readContext):
      return original(f, off)
    read.terminal

  proc installFlatReadBody(f: var FlatFrame, info: NativeReadBodyInfo) =
    ## Rebuild the typed certificate before installing a body-only stream patch.
    assert f.nativeOriginal == nil
    if int(info.first) >= f.plan.facts.len or
        not matchesNativeReadBody(f.nativeSession, buildFlatReadBody(f,
          f.plan.facts[int(info.first)].pc, info.epoch)):
      invalidateNativeStream(f.nativeSession)
      return
    let entry = info.header+1
    f.nativeOriginal = f.handlers[int(entry)]
    f.nativeEntry = entry
    f.nativeInstalledEpoch = info.epoch
    f.handlers[int(entry)] = flatNativeReadBody
