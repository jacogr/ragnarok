# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Cold copied source certificate for the connected shared read cycle.

when declared(FlatFrame):
  const ConnectedReadOpcodes = [2'u8, 124, 151, 130, 200, 129, 51, 151,
    152, 130, 198, 132, 198, 130, 197, 212, 151, 152, 130, 198, 130, 197, 212, 1]
    ## The exact original Read block, including its folded noop and checked fallthrough.

  type FlatCyclePart = object ## A temporary complete block and its original operands.
    site: NativeCycleSite
    terminal: uint32
    operations: array[24, NativeOperation]

  func flatCycleHeader(f: FlatFrame, pc: uint32, header: var uint32): bool =
    ## Only a cached complete original target can become an internal or checked successor.
    var source = default(FlatSourceInterval)
    flatCompleteOriginalHeader(f, pc, high(uint32), header, source) and header < NativeEntryLimit

  proc flatCyclePart(f: FlatFrame, header: uint32, opcodes: openArray[byte],
      part: var FlatCyclePart): bool =
    ## Bind one original priced interval without depending on a fused header handler.
    if header >= NativeEntryLimit or int(header) >= f.sites.len or opcodes.len == 0 or
        opcodes.len > part.operations.len: return false
    let first = f.sites[int(header)]
    if int(first) >= f.plan.facts.len: return false
    let pc = f.plan.facts[int(first)].pc
    var resolved = 0'u32
    var source = default(FlatSourceInterval)
    if not flatCompleteOriginalHeader(f, pc, uint32(opcodes.len), resolved, source) or
        resolved != header or source.span != uint32(opcodes.len): return false
    let price = blockGas(f.plan.source, CodeAddress(uint64(pc)), f.plan.cycles)
    if price.error != GasError.None or uint64(price.value) != source.price: return false
    var walk = default(FlatSourceSummary)
    if not flatWalkCompleteSource(f, header, source, walk): return false
    part = default(FlatCyclePart)
    part.site = NativeCycleSite(header: header, first: first, price: source.price)
    part.terminal = walk.terminal
    var node = header + 1
    for index in 0..<opcodes.len:
      # The immutable fact is the opcode authority, including an original folded noop.
      let fact = f.plan.facts[int(first) + index]
      if fact.opcode != opcodes[index] or fact.priceIndex != f.plan.facts[int(first)].priceIndex:
        return false
      if fact.opcode == 2: continue
      let decoded = flatSourcePayload(f.plan, fact)
      let args = f.arguments[int(node)]
      if node != walk.terminal and (args.x != decoded.args.x or args.y != decoded.args.y or
          args.slots != decoded.args.slots): return false
      # Conditional payloads pack a target beside the original sign-extended immediate.
      let immediate = if fact.opcode in {81'u8..90'u8, 170'u8..175'u8}:
        flatSext32(uint32(decoded.args.x and 0xffffffff'u64))
      else: decoded.args.x
      part.operations[index] = NativeOperation(opcode: fact.opcode, slots: decoded.args.slots,
        immediate: immediate)
      inc node
    true

  proc flatCycleJump[Code: static[int]](f: FlatFrame, part: FlatCyclePart,
      target: var uint32): bool =
    ## Reconcile the original static edge with the already resolved stream coordinate.
    let cached: FlatHandler = flatCachedJump[Code]
    let unresolved: FlatHandler = flatJump[Code]
    if f.handlers[int(part.terminal)] != cached: return false
    let fact = f.plan.facts[int(f.sites[int(part.terminal)])]
    let original = flatSourcePayload(f.plan, fact)
    original.handler == unresolved and flatCycleHeader(f, original.args.y, target) and
      f.arguments[int(part.terminal)].y == target

  proc flatCycleBranch[Code: static[int]](f: FlatFrame, part: FlatCyclePart,
      yes, no: var uint32): bool =
    ## Certify both cached arms and the original predicate operands.
    let cached: FlatHandler = flatBranch[Code]
    let unresolved: FlatHandler = flatUnresolvedBranch[Code]
    if f.handlers[int(part.terminal)] != cached: return false
    let fact = f.plan.facts[int(f.sites[int(part.terminal)])]
    let original = flatSourcePayload(f.plan, fact)
    let args = f.arguments[int(part.terminal)]
    original.handler == unresolved and
      args.slots == original.args.slots and
      (args.x and 0xffffffff'u64) == (original.args.x and 0xffffffff'u64) and
      flatCycleHeader(f, uint32(original.args.x shr 32), yes) and
      flatCycleHeader(f, original.args.y, no) and uint32(args.x shr 32) == yes and args.y == no

  proc buildFlatReadCycle(f: FlatFrame, read: NativeReadBody): NativeReadCycle =
    ## Extend a real read nomination only when the complete bounded route is source certified.
    const R = NativeCycleRole.Read
    const P = NativeCycleRole.StoreSetup
    const S = NativeCycleRole.Store
    const T = NativeCycleRole.Tail
    const J = NativeCycleRole.Jump
    const O = NativeCycleRole.Outer
    const G = NativeCycleRole.Gate
    result = default(NativeReadCycle)
    if f.plan == nil or f.plan.allowNative or f.plan.singleStep or f.pricingKind != 0 or
        f.preparationFailure != FlatError.None or not read.complete or read.len != 25: return
    let info = read.info
    let continuation = read.continuationInfo
    if info.epoch != nativeEpoch(f.nativeSession) or continuation.terminal == 0: return
    var cycle = default(NativeReadCycle)
    var part = default(FlatCyclePart)
    if not flatCyclePart(f, info.header, ConnectedReadOpcodes, part) or
        part.site.first != info.first or part.terminal != info.terminal: return
    cycle.layout.sites[R] = part.site
    var next = 0'u32
    if not flatCycleJump[1](f, part, next) or next != continuation.header: return
    if not flatCyclePart(f, next, [51'u8, 200, 149, 1], part) or
        part.site.price != continuation.price or part.terminal != continuation.terminal: return
    cycle.layout.sites[P] = part.site
    if not flatCycleJump[1](f, part, next): return
    if not flatCyclePart(f, next, [198'u8, 120, 149, 149, 171], part) or
        f.handlers[int(next)] != flatChargedWordLoop or not flatWordShape(f, next) or
        part.site.price > high(uint64) div NativeCycleGroupVisits: return
    cycle.layout.sites[S] = part.site
    let prefix = part.operations[0]
    let store = part.operations[1]
    cycle.word = NativeCycleWord(valueLane: prefix.slots.aIndex, shiftLane: prefix.slots.bIndex,
      byteLane: prefix.slots.destinationIndex, baseLane: store.slots.bIndex,
      boundLane: part.operations[4].slots.bIndex, displacement: store.immediate)
    var yes = 0'u32
    var no = 0'u32
    if not flatCycleBranch[171](f, part, yes, no) or yes != next: return
    if not flatCyclePart(f, no, [2'u8, 57, 131, 173], part): return
    cycle.layout.sites[T] = part.site
    cycle.tailLoad = part.operations[1]
    cycle.tailStep = part.operations[2]
    cycle.tailBranch = part.operations[3]
    if not flatCycleBranch[173](f, part, yes, no) or yes != cycle.layout.sites[P].header: return
    if not flatCyclePart(f, no, [40'u8], part): return
    cycle.layout.sites[J] = part.site
    if not flatCycleJump[40](f, part, next): return
    if not flatCyclePart(f, next, [131'u8, 149, 81], part): return
    cycle.layout.sites[O] = part.site
    cycle.outer = [part.operations[0], part.operations[1], part.operations[2]]
    if not flatCycleBranch[81](f, part, yes, no): return
    cycle.layout.outsideHeader = yes
    if not flatCyclePart(f, no, [88'u8], part): return
    cycle.layout.sites[G] = part.site
    cycle.gate = part.operations[0]
    if not flatCycleBranch[88](f, part, yes, no) or yes != cycle.layout.sites[O].header or
        no != cycle.layout.sites[R].header: return
    for role in NativeCycleRole:
      # Distinct source intervals and headers keep each charged unit's authority separate.
      let site = cycle.layout.sites[role]
      if site.header == cycle.layout.outsideHeader: return
      for previous in NativeCycleRole:
        # Each pair is compared once, with widened original ordinal arithmetic.
        if ord(previous) >= ord(role): break
        let other = cycle.layout.sites[previous]
        if site.header == other.header or (uint64(site.first) + NativeCycleSpans[role] >
            uint64(other.first) and uint64(other.first) + NativeCycleSpans[previous] >
            uint64(site.first)): return
    cycle.read = read
    result = cycle

  proc flatNativeReadCycle(f: var FlatFrame, off: uint32): uint32 =
    ## All borrows and the reservation receipt belong to this invocation only.
    let original = f.nativeOriginal
    assert original != nil and off == f.nativeEntry
    let read = nativeReadCycleInfo(f.nativeSession)
    if read.epoch == 0 or read.epoch != f.nativeInstalledEpoch or off != read.header+1 or
        f.pricingKind != 0 or f.barrier != flatStop or not f.info.blockCharged or
        f.reservation != (read.header or flatReservationHeaderFlag):
      return original(f, off)
    if not f.readContextReady: prepareFlatReadContext(f)
    var context = NativeCycleContext(read: f.readContext, gas: uint64(f.info.gas),
      remaining: f.remaining, lastCompleted: NativeCycleNoCompleted)
    context.writable[0] = NativeCycleWritable(first: f.stackBase, length: uint64(f.stack.len))
    context.writable[1] = NativeCycleWritable(first: f.rwBase, length: uint64(f.rw.len))
    if f.stack.len > 0: context.writable[0].data = addr f.stack[0]
    if f.rw.len > 0: context.writable[1].data = addr f.rw[0]
    if f.dirtyPages.len > 0: context.dirty = addr f.dirtyPages[0]
    context.dirtyWords = uint64(f.dirtyPages.len)
    var lastHeader = read.header
    result = runNativeCycle(f.nativeSession, f.info.registers, context, lastHeader)
    f.info.gas = MachineGas(context.gas)
    f.remaining = context.remaining
    if context.paidRead == 1:
      # Reenter the saved scalar body exactly once with the paid read header and live prior stores.
      f.reservation = read.header or flatReservationHeaderFlag
      return original(f, off)
    f.info.blockCharged = false
    f.reservation = lastHeader or flatReservationHeaderFlag

  proc installFlatReadCycle(f: var FlatFrame, info: NativeReadBodyInfo) =
    ## Patch the same body entry only after rebuilding the complete connected certificate.
    assert f.nativeOriginal == nil
    if int(info.first) >= f.plan.facts.len:
      invalidateNativeStream(f.nativeSession)
      return
    var body = buildFlatReadBody(f, f.plan.facts[int(info.first)].pc, info.epoch)
    if not extendFlatReadBody(f, body) or
        not matchesNativeReadCycle(f.nativeSession, buildFlatReadCycle(f, body)):
      invalidateNativeStream(f.nativeSession)
      return
    let entry = info.header+1
    f.nativeOriginal = f.handlers[int(entry)]
    f.nativeEntry = entry
    f.nativeInstalledEpoch = info.epoch
    f.handlers[int(entry)] = flatNativeReadCycle
