# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Checked source certificate and invocation bridge for a bounded native read body.

when declared(FlatFrame):
  proc flatReadTerminal(f: FlatFrame, node: uint32, fact: FlatFact): bool =
    ## The original static fallthrough remains checked, whether the stream cached it or not.
    if fact.opcode != 1 or not fact.ending or not fact.fallthrough: return false
    var payload = default(FlatSourcePayload)
    if not tryFlatSourcePayload(f.plan, fact, payload): return false
    if payload.handler != flatJump[1]: return false
    let target = f.arguments[int(node)].y
    if f.handlers[int(node)] == flatJump[1]: return target == fact.next
    if f.handlers[int(node)] != flatCachedJump[1] or
        int(fact.next) >= f.compiledForPc.len or int(target) >= f.sites.len or
        int(target) >= f.handlers.len or target >= flatReservationHeaderFlag: return false
    let targetFact = f.sites[int(target)]
    var destination = default(FlatFact)
    var packed = 0'u32
    tryReadFlatFact(f, int(targetFact), destination) and destination.pc == fact.next and
      tryReadMetadata(f.compiledForPc, int(fact.next), packed) and
      packed == (target or flatReservationHeaderFlag)+1

  proc buildFlatReadBody(f: FlatFrame, pc: uint32, epoch: uint64): NativeReadBody =
    ## Bind one ordinary complete header, original operations and its unmodified checked terminal.
    result = default(NativeReadBody)
    if f.plan == nil or f.plan.allowNative or f.plan.singleStep or f.pricingKind != 0 or
        f.preparationFailure != FlatError.None: return
    var header = 0'u32
    var source = default(FlatSourceInterval)
    if not flatCompleteOriginalHeader(f, pc, NativeReadFactLimit, header, source): return
    var root = default(FlatFact)
    if not tryReadFlatFact(f, int(source.first), root) or f.handlers[int(header)] != flatCharge or
        root.opcode != 2: return
    var walk = default(FlatSourceSummary)
    var ending = default(FlatFact)
    if not flatWalkCompleteSource(f, header, source, walk) or
        not tryReadFlatFact(f, int(source.last), ending) or
        not flatReadTerminal(f, walk.terminal, ending): return
    var body = initNativeReadBody(header, walk.terminal, source.first, source.last, epoch)
    var ordinal = source.first+1
    var node = header+1
    while ordinal < source.last:
      # The initial noop is the only folded fact this first shape accepts.
      var fact = default(FlatFact)
      if not tryReadFlatFact(f, int(ordinal), fact): return
      if fact.opcode == 2 or node >= walk.terminal or f.sites[int(node)] != ordinal or
          fact.priceIndex != root.priceIndex: return
      let args = f.arguments[int(node)]
      var payload = default(FlatSourcePayload)
      if not tryFlatSourcePayload(f.plan, fact, payload): return
      if args.x != payload.args.x or args.y != payload.args.y or args.slots !=
          payload.args.slots: return
      if not addReadBodyOperation(body, node, ordinal, NativeOperation(opcode: fact.opcode,
          slots: payload.args.slots, immediate: payload.args.x)): return
      inc ordinal
      inc node
    if body.complete: result = body

  proc extendFlatReadBody(f: FlatFrame, body: var NativeReadBody): bool =
    ## Bind one already-cached ordinary fallthrough with three original scalar operations.
    if not body.complete: return false
    let info = body.info
    if f.handlers[int(info.terminal)] != flatCachedJump[1]: return false
    var terminal = default(FlatFact)
    if not tryReadFlatFact(f, int(info.last), terminal): return false
    let nextPc = terminal.next
    var header = 0'u32
    var source = default(FlatSourceInterval)
    if not flatCompleteOriginalHeader(f, nextPc, NativeReadContinuationSpan, header, source) or
        f.arguments[int(info.terminal)].y != header or f.handlers[int(header)] != flatCharge or
        source.span != NativeReadContinuationSpan or source.first != info.last+1: return false
    var walk = default(FlatSourceSummary)
    if not flatWalkCompleteSource(f, header, source, walk) or
        walk.operations != NativeReadContinuationSpan or
        f.handlers[int(walk.terminal)] != flatCachedJump[1] or
        not tryReadFlatFact(f, int(source.last), terminal) or
        not flatReadTerminal(f, walk.terminal, terminal): return false
    var operations = default(array[NativeReadContinuationSpan.int-1, NativeOperation])
    var first = default(FlatFact)
    if not tryReadFlatFact(f, int(source.first), first): return false
    let priceIndex = first.priceIndex
    for index in 0..<operations.len:
      var fact = default(FlatFact)
      if not tryReadFlatFact(f, int(source.first)+index, fact): return false
      let args = f.arguments[int(header)+1+index]
      if fact.priceIndex != priceIndex: return false
      var payload = default(FlatSourcePayload)
      if not tryFlatSourcePayload(f.plan, fact, payload): return false
      if args.x != payload.args.x or args.y != payload.args.y or
          args.slots != payload.args.slots: return false
      operations[index] = NativeOperation(opcode: fact.opcode, slots: payload.args.slots,
        immediate: payload.args.x)
    addNativeReadContinuation(body, NativeReadContinuation(header: header,
      terminal: walk.terminal, price: source.price), operations)

  proc flatRWReadRegion(first: uint64, bytes: RWView, region: var NativeReadRegion): bool =
    ## Prove the complete live RW span before constructing a native descriptor; empty success grants no byte access.
    var span = default(RWSpan)
    if not tryBorrowRWSpan(bytes, 0, bytes.len, span): return false
    region = initNativeReadRegion(first, span.toOpenArray)
    true

  proc prepareFlatReadContext(f: var FlatFrame): bool {.noinline.} =
    ## Publish descriptors only after the RW borrow succeeds; a failed rebuild leaves the earlier context untouched.
    var writable = default(NativeReadRegion)
    if not flatRWReadRegion(f.rwBase, f.rw, writable): return false
    f.readContext = [initNativeReadRegion(f.stackBase, f.stack), writable,
      initNativeReadRegion(f.roBase, f.ro)]
    f.readContextReady = true
    true

  proc flatNativeReadBody(f: var FlatFrame, off: uint32): uint32 =
    ## Require the exact complete reservation. Refusal replays the original paid body.
    let original = f.nativeOriginal
    if original == nil or off != f.nativeEntry:
      return flatLocal(f, off, oracle.StepError.BackendFailure)
    let read = nativeReadInfo(f.nativeSession)
    if read.epoch == 0 or read.epoch != f.nativeInstalledEpoch or off != read.header+1 or
        not matchesNativeImage(f.nativeSession, f.nativeInstallation.key,
            NativeKind.CheckedReadBody) or
        f.pricingKind != 0 or f.barrier != flatStop or not f.info.blockCharged or
        f.reservation != (read.header or flatReservationHeaderFlag):
      return original(f, off)
    if not f.readContextReady and not prepareFlatReadContext(f):
      return flatLocal(f, off, oracle.StepError.BackendFailure)
    case runNativeReadBody(f.nativeSession, f.info.registers, f.readContext)
    of NativeReadOutcome.Completed: read.terminal
    of NativeReadOutcome.Refused: original(f, off)
    of NativeReadOutcome.Failed: flatLocal(f, off, oracle.StepError.BackendFailure)

  proc runFlatReadContinuationCold(f: var FlatFrame): NativeReadOutcome {.noinline.} =
    ## Publish fresh descriptors only once the combined register transaction commits.
    var writable = default(NativeReadRegion)
    if not flatRWReadRegion(f.rwBase, f.rw, writable): return NativeReadOutcome.Failed
    var context = [initNativeReadRegion(f.stackBase, f.stack), writable,
      initNativeReadRegion(f.roBase, f.ro)]
    result = runNativeReadBody(f.nativeSession, f.info.registers, context)
    if result == NativeReadOutcome.Completed:
      f.readContext = context
      f.readContextReady = true

  proc flatNativeReadContinuation(f: var FlatFrame, off: uint32): uint32 =
    ## Preflight the successor against the counters left by the first paid reservation.
    let original = f.nativeOriginal
    if original == nil or off != f.nativeEntry:
      return flatLocal(f, off, oracle.StepError.BackendFailure)
    let read = nativeReadInfo(f.nativeSession)
    if read.epoch == 0 or read.epoch != f.nativeInstalledEpoch or off != read.header+1 or
        not matchesNativeImage(f.nativeSession, f.nativeInstallation.key,
            NativeKind.CheckedReadBody) or
        f.pricingKind != 0 or f.barrier != flatStop or not f.info.blockCharged or
        f.reservation != (read.header or flatReservationHeaderFlag):
      return original(f, off)
    let continuation = nativeReadContinuation(f.nativeSession)
    if f.remaining < uint64(NativeReadContinuationSpan) or uint64(f.info.gas) < continuation.price:
      return original(f, off)
    let committed = if f.readContextReady:
      runNativeReadBody(f.nativeSession, f.info.registers, f.readContext)
    else:
      runFlatReadContinuationCold(f)
    case committed
    of NativeReadOutcome.Refused: return original(f, off)
    of NativeReadOutcome.Failed: return flatLocal(f, off, oracle.StepError.BackendFailure)
    of NativeReadOutcome.Completed: discard
    # The first cached fallthrough clears the paid bit and the second header immediately sets it.
    f.info.gas = MachineGas(uint64(f.info.gas)-continuation.price)
    f.remaining-=uint64(NativeReadContinuationSpan)
    f.reservation = continuation.header or flatReservationHeaderFlag
    continuation.terminal

  proc validateFlatReadNomination(f: var FlatFrame) =
    ## Reconstruct every original operand and optional continuation at the saved coordinates after restoration.
    let info = deferredNativeReadInfo(f.nativeSession)
    if info.epoch == 0: return
    if int(info.first) >= f.plan.facts.len:
      invalidateNativeStream(f.nativeSession)
      return
    var first = default(FlatFact)
    if not tryReadFlatFact(f, int(info.first), first):
      invalidateNativeStream(f.nativeSession)
      return
    var body = buildFlatReadBody(f, first.pc, info.epoch)
    let extended = nativeReadContinuation(f.nativeSession).terminal != 0
    if (extended and not extendFlatReadBody(f, body)) or
        not validateNativeRead(f.nativeSession, body):
      # Changed geometry or operands revoke the nomination rather than authorizing stale code.
      invalidateNativeStream(f.nativeSession)
      when NativeReadCycleEnabled:
        return
    when NativeReadCycleEnabled:
      if nativeCycleNominated(f.nativeSession):
        validateNativeCycleNomination(f.nativeSession, buildFlatReadCycle(f, body))

  proc installFlatReadBody(f: var FlatFrame, info: NativeReadBodyInfo) =
    ## Rebuild the typed certificate before installing a body-only stream patch.
    if f.nativeOriginal != nil or f.plan == nil:
      f.reason = oracle.StepError.BackendFailure
      return
    if int(info.first) >= f.plan.facts.len:
      invalidateNativeStream(f.nativeSession)
      return
    var first = default(FlatFact)
    if not tryReadFlatFact(f, int(info.first), first):
      invalidateNativeStream(f.nativeSession)
      return
    var body = buildFlatReadBody(f, first.pc, info.epoch)
    let extended = nativeReadContinuation(f.nativeSession).terminal != 0
    if (extended and not extendFlatReadBody(f, body)) or
        not matchesNativeReadBody(f.nativeSession, body):
      invalidateNativeStream(f.nativeSession)
      return
    let entry = info.header+1
    if uint64(entry) >= uint64(f.handlers.len):
      f.reason = oracle.StepError.BackendFailure
      return
    let original = f.handlers[int(entry)]
    if not flatInstallNativePatch(f, entry,
        if extended: flatNativeReadContinuation else: flatNativeReadBody): return
    f.nativeOriginal = original
    f.nativeEntry = entry
    f.nativeInstalledEpoch = info.epoch
