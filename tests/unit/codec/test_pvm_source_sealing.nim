# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Source-only admission, every interior entry/prefix, selected pricing, frozen code and exclusive source reuse.
import std/[assertions, syncio]
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine, gas, gas_plan, gas_memo, step]
import ../../../src/pvm/internal/handler_stream

proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Fixture framing uses an independent public codec, never production assembler state.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len: bytes.add(encoded.bytes[index])

proc owner(parts: openArray[seq[byte]], jumps: openArray[uint32] = []): Program =
  ## Explicit opcode boundaries admit arbitrary interior entries without marking operand bytes.
  var bytes: seq[byte] = @[]
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    starts.add(code.len)
    for value in part: code.add(value)
  appendNatural(bytes, uint64(jumps.len))
  bytes.add(if jumps.len == 0: 0'u8 else: 4'u8)
  appendNatural(bytes, uint64(code.len))
  for target in jumps:
    for shift in 0..<4: bytes.add(byte((uint64(target) shr (shift*8)) and 255))
  for value in code: bytes.add(value)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for value in mask: bytes.add(value)
  let decoded = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(4194304), JumpCountLimit(1024))
  assert decoded.error == ProgramError.None, "source sealing line 32: decoded.error == ProgramError.None"
  decoded.value

proc plan(source: Program, limits: FlatLimits = defaultFlatLimits(),
    cycles: GasCycleLimit = GasCycleLimit(100000), native: bool = true): FlatPlan =
  ## Only an admitted plan supplies the hook's policy and immutable source authority.
  var admitted = prepareFlatPlan(source, cycles, limits, allowNative = native)
  assert admitted.error == FlatError.None, "source sealing line 39: admitted.error == FlatError.None"
  takeValue(admitted)

proc same(left, right: FlatFrame, context: string = "") =
  ## Compare full CPU, paid state, attempt balance, source/exit metadata and immutable source observations.
  assert left.reason == right.reason and left.exit == right.exit,
    context & " error/exit actual=" & $left.reason & "/" & $left.exit &
    " expected=" & $right.reason & "/" & $right.exit
  assert left.info.pc == right.info.pc and left.info.gas == right.info.gas,
    context & " pc/gas actual=" & $uint64(left.info.pc) & "/" & $uint64(left.info.gas) &
    " expected=" & $uint64(right.info.pc) & "/" & $uint64(right.info.gas)
  assert left.info.gasDeficit == right.info.gasDeficit, "source sealing line 46: left.info.gasDeficit == right.info.gasDeficit"
  assert left.info.blockCharged == right.info.blockCharged, context & " prepaid state differs"
  assert left.info.registers == right.info.registers and left.remaining == right.remaining,
    context & " registers/source-attempt balance differs; actual remaining=" & $left.remaining &
    " expected=" & $right.remaining
  assert left.faultPage == right.faultPage and left.hostCall == right.hostCall, "source sealing line 49: left.faultPage == right.faultPage and left.hostCall == right.hostCall"
  checkFlatSource(left)
  checkFlatSource(right)

proc frozen(stream: FlatStream, before: FlatSealedInfo, nodes, work: uint64,
    native: array[7, uint64]) =
  ## Construction observations freeze independently of live native calls/operations and host events.
  assert streamSealedInfo(stream) == before, "source sealing line 56: streamSealedInfo(stream) == before"
  assert streamNodes(stream) == nodes and streamPreparation(stream) == work, "source sealing line 57: streamNodes(stream) == nodes and streamPreparation(stream) == work"
  when defined(pvmX86Jit) or defined(pvmArm64Jit):
    let after = streamNativeStatistics(stream)
    for index in [0, 3, 4]: assert after[index] == native[index], "source sealing line 60: after[index] == native[index]"

proc entries(parts: openArray[seq[byte]], images: openArray[PageImage] = [],
    registers: RegisterFile = default(RegisterFile), jumps: openArray[uint32] = []) =
  ## Every genuine PC, paid flag, gas edge and partial source prefix shares the same sealed bodies.
  let source = owner(parts, jumps)
  let compiled = plan(source)
  let checked = plan(source, native = false)
  var prepared = prepareFlatStream(compiled)
  assert prepared.error == FlatError.None, "source sealing line 69: prepared.error == FlatError.None"
  var stream = takeValue(prepared)
  let info = streamSealedInfo(stream)
  let nodes = streamNodes(stream)
  let work = streamPreparation(stream)
  var statistics = default(array[7, uint64])
  when defined(pvmX86Jit) or defined(pvmArm64Jit): statistics = streamNativeStatistics(stream)
  assert info.sealed and info.candidates == uint64(parts.len), "source sealing line 76: info.sealed and info.candidates == uint64(parts.len)"
  assert info.nativeEntries+info.checkedEntries+info.capacityDeferred == info.candidates, "source sealing line 77: info.nativeEntries+info.checkedEntries+info.capacityDeferred == info.candidates"
  var pc = 0'u64
  for part in parts:
    for paid in [false, true]:
      for gas in [0'u64, 1, 10000]:
        for attempts in 0..parts.len+1:
          # Paid resumes and zero budgets must retain the original reservation/error order at every interior start.
          let cpu = MachineInfo(pc: CodeAddress(pc), gas: MachineGas(gas),
            blockCharged: paid, registers: registers)
          var actual = newFlatFrame(compiled, images, cpu)
          var expected = newFlatFrame(checked, images, cpu)
          restoreFlatStream(actual, stream)
          runFlat(actual, uint64(attempts))
          runFlat(expected, uint64(attempts))
          same(actual, expected, "entry pc=" & $pc & " opcode=" & $part[0] &
            " prefix=" & $attempts & " paid=" & $paid & " gas=" & $gas)
          let a = flatMemorySnapshot(actual)
          let b = flatMemorySnapshot(expected)
          for image in images:
            let left = pageImage(a, image.index).value
            let right = pageImage(b, image.index).value
            assert left.access == right.access and left.bytes == right.bytes, "source sealing line 97: left.access == right.access and left.bytes == right.bytes"
          stream = takeFlatStream(actual)
          frozen(stream, info, nodes, work, statistics)
    pc+=uint64(part.len)

when defined(pvmArm64Jit) and not defined(pvmX86Jit) and defined(pvmSourceSealingReceipt):
  proc narrowReadClass(prefix, reads: int): uint8 =
    ## Compare a specific source entry before/after native coordinate saturation through the shared real builder.
    var parts: seq[seq[byte]] = @[]
    for index in 0..<prefix: parts.add(@[0'u8])
    for index in 0..<reads: parts.add(@[124'u8, 16])
    parts.add(@[0'u8])
    var admitted = prepareFlatStream(plan(owner(parts)))
    assert admitted.error == FlatError.None, "ARM narrow-read classification construction"
    var stream = takeValue(admitted)
    let snapshot = streamSealedInfo(stream)
    assert snapshot.candidates == snapshot.nativeEntries+snapshot.checkedEntries+snapshot.capacityDeferred,
      "ARM narrow-read source-entry partition"
    streamSealedEntry(stream, CodeAddress(uint64(prefix)))

let pure = owner([@[100'u8, 16, 1], @[100'u8, 16, 2], @[100'u8, 16, 3],
  @[100'u8, 16, 4], @[0'u8]])
var defaulted = default(FlatResult[FlatStream])
assert defaulted.error == FlatError.Uninitialized, "source sealing line 105: defaulted.error == FlatError.Uninitialized"
var disabled = prepareFlatStream(plan(pure, native = false))
assert disabled.error == FlatError.InvalidPolicy, "source sealing line 107: disabled.error == FlatError.InvalidPolicy"
var unavailable = prepareFlatStream(plan(pure))
when not defined(pvmX86Jit) and not defined(pvmArm64Jit):
  # A missing generator cannot silently publish an explicit eager all-fallback owner.
  assert unavailable.error == FlatError.NativeNotBuilt, "source sealing line 111: unavailable.error == FlatError.NativeNotBuilt"
elif defined(pvmX86Jit) and not (defined(linux) and defined(amd64)):
  # A built generator cannot grant an executable capability on a different host ABI.
  assert unavailable.error == FlatError.NativePlatformUnsupported, "source sealing line 114: unavailable.error == FlatError.NativePlatformUnsupported"
elif not defined(pvmX86Jit) and not (defined(arm64) and (defined(linux) or defined(macosx))):
  assert unavailable.error == FlatError.NativePlatformUnsupported, "source sealing line 116: unavailable.error == FlatError.NativePlatformUnsupported"
elif defined(pvmX86JitRefuse) or defined(pvmArm64JitRefuse):
  # Native storage refusal must precede any usable stream, including unsupported source.
  assert unavailable.error == FlatError.NativeStorageUnavailable, "source sealing line 119: unavailable.error == FlatError.NativeStorageUnavailable"
  let fallback = owner([@[0'u8]])
  var refused = prepareFlatStream(plan(fallback))
  assert refused.error == FlatError.NativeStorageUnavailable, "source sealing line 122: refused.error == FlatError.NativeStorageUnavailable"
else:
  assert unavailable.error == FlatError.None, "source sealing line 124: unavailable.error == FlatError.None"
  var reusable = takeValue(unavailable)
  let originalInfo = streamSealedInfo(reusable)
  let originalNative = streamNativeStatistics(reusable)
  let originalNodes = streamNodes(reusable)
  let originalWork = streamPreparation(reusable)
  assert originalInfo.nativeEntries > 0 and originalNative[0] > 0 and originalNative[3] > 0, "source sealing line 130: originalInfo.nativeEntries > 0 and originalNative[0] > 0 and originalNative[3] > 0"
  when defined(pvmSourceSealingReceipt): assert originalInfo.compilationPasses > 0, "source sealing line 131: originalInfo.compilationPasses > 0"
  assert originalNative[1] == 0 and originalNative[2] == 0,
      "source sealing line 132: originalNative[1] == 0 and originalNative[2] == 0" # Construction never executes guest/native operations.
  let sourcePlan = plan(pure)
  var wrong = newFlatFrame(sourcePlan, [], MachineInfo(gas: MachineGas(10000)))
  restoreFlatStream(wrong, reusable)
  assert preparationError(wrong) == FlatError.InvalidProgram, "source sealing line 136: preparationError(wrong) == FlatError.InvalidProgram"
  frozen(reusable, originalInfo, originalNodes, originalWork, originalNative)

  # Fresh construction binds the stream to this exact plan, independently of equal source bytes.
  var prepared = prepareFlatStream(sourcePlan)
  assert prepared.error == FlatError.None, "source sealing line 141: prepared.error == FlatError.None"
  reusable = takeValue(prepared)
  let frozenNative = streamNativeStatistics(reusable)
  let frozenInfo = streamSealedInfo(reusable)
  let frozenNodes = streamNodes(reusable)
  let frozenWork = streamPreparation(reusable)
  for repeat in 0..<3:
    var frame = newFlatFrame(sourcePlan, [], MachineInfo(gas: MachineGas(10000)))
    restoreFlatStream(frame, reusable)
    runFlat(frame, 100)
    assert frame.reason == StepError.None and frame.exit == StepExit.Panic, "source sealing line 151: frame.reason == StepError.None and frame.exit == StepExit.Panic"
    # Mapping replacement moves all frozen construction state with the exact same code owner.
    assert replaceFlatMemoryChecked(frame, [], MachineInfo(gas: MachineGas(10000))) ==
        FlatError.None, "source sealing line 153: replaceFlatMemoryChecked(frame, [], MachineInfo(gas: MachineGas(10000))) == FlatError.None"
    runFlat(frame, 100)
    reusable = takeFlatStream(frame)
    frozen(reusable, frozenInfo, frozenNodes, frozenWork, frozenNative)
    when defined(pvmSourceSealingReceipt):
      assert streamSealedEntry(reusable, CodeAddress(0)) == 1,
        "copied per-source classification survives repeated leases and mapping replacement"
  let live = streamNativeStatistics(reusable)
  assert live[1] > frozenNative[1] and live[2] > frozenNative[2], "source sealing line 158: live[1] > frozenNative[1] and live[2] > frozenNative[2]"

  # Entry at either member of both retained register folds and differing pair groups must preserve all aliases.
  entries([@[151'u8, 16, 1], @[152'u8, 16, 1], @[131'u8, 16, 1], @[2'u8],
    @[200'u8, 16, 2], @[139'u8, 16, 3], @[2'u8], @[2'u8], @[0'u8]])
  entries([@[149'u8, 0, 1], @[149'u8, 0, 2], @[149'u8, 0, 3],
    @[100'u8, 0, 4], @[100'u8, 0, 5], @[0'u8]])
  entries([@[2'u8], @[2'u8], @[2'u8], @[0'u8]])
  # Both conditional arms and a backward edge remain source-static resolution without native promotion.
  entries([@[100'u8, 16, 1], @[100'u8, 16, 2], @[100'u8, 16, 3],
    @[100'u8, 16, 4], @[81'u8, 16, 3], @[0'u8]])
  entries([@[100'u8, 16, 1], @[100'u8, 16, 2], @[100'u8, 16, 3],
    @[100'u8, 16, 4], @[81'u8, 16, 244], @[0'u8]])
  # A genuine dynamic jump-table target and host continuation may enter a different prepared block.
  var dynamicRegs = default(RegisterFile)
  dynamicRegs[0] = RegisterValue(2)
  entries([@[50'u8, 0], @[100'u8, 16, 1], @[10'u8, 0], @[0'u8]],
    registers = dynamicRegs, jumps = [2'u32])

  var images = [PageImage(index: PageIndex(16), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(17), access: PageAccess.ReadOnly)]
  for offset in 0..<4096: images[0].bytes[offset] = byte(offset mod 251)
  var regs = default(RegisterFile)
  regs[1] = RegisterValue(65536)
  entries([@[124'u8, 16], @[125'u8, 17], @[126'u8, 18], @[127'u8, 19],
    @[128'u8, 20], @[129'u8, 21], @[130'u8, 22], @[100'u8, 16, 1],
    @[100'u8, 16, 2], @[100'u8, 16, 3], @[0'u8]], images, regs)
  entries([@[120'u8, 16], @[124'u8, 16], @[2'u8], @[0'u8]], images, regs)

  for opcode in 0..255:
    # Bounded deterministic operand/alias patterns cover every valid opcode through every genuine entry and prefix.
    if not validOpcode(byte(opcode)): continue
    for pattern in [0'u8, 17, 255]:
      var operation = @[byte(opcode)]
      for operand in 0..<24: operation.add(pattern)
      entries([operation, @[2'u8], @[100'u8, 16, 1], @[0'u8]])

  # All-fallback ownership still binds the exact admitted plan, even though no native body exists.
  let fallbackSource = owner([@[0'u8]])
  let fallbackPlan = plan(fallbackSource)
  var fallbackResult = prepareFlatStream(fallbackPlan)
  assert fallbackResult.error == FlatError.None, "source sealing line 199: fallbackResult.error == FlatError.None"
  var fallbackStream = takeValue(fallbackResult)
  assert streamSealedInfo(fallbackStream).nativeEntries == 0, "source sealing line 201: streamSealedInfo(fallbackStream).nativeEntries == 0"
  assert streamNativeStatistics(fallbackStream)[0] == 0, "source sealing line 202: streamNativeStatistics(fallbackStream)[0] == 0"
  var otherFallback = newFlatFrame(plan(fallbackSource), [], MachineInfo(gas: MachineGas(100)))
  restoreFlatStream(otherFallback, fallbackStream)
  assert preparationError(otherFallback) == FlatError.InvalidProgram, "source sealing line 205: preparationError(otherFallback) == FlatError.InvalidProgram"
  assert streamSealedInfo(fallbackStream).sealed, "source sealing line 206: streamSealedInfo(fallbackStream).sealed"

  # Synchronous host repair replaces mappings and permissions while the same shared interior bodies remain sealed.
  let hosted = owner([@[10'u8, 3], @[124'u8, 16], @[10'u8, 4], @[0'u8]])
  let hostPlan = plan(hosted)
  var hostResult = prepareFlatStream(hostPlan)
  assert hostResult.error == FlatError.None, "source sealing line 212: hostResult.error == FlatError.None"
  var hostStream = takeValue(hostResult)
  let hostNative = streamNativeStatistics(hostStream)
  let hostInfo = streamSealedInfo(hostStream)
  let hostNodes = streamNodes(hostStream)
  let hostWork = streamPreparation(hostStream)
  let hostCpu = MachineInfo(gas: MachineGas(10000), registers: regs)
  var hostFrame = newFlatFrame(hostPlan, images, hostCpu)
  var hostExpected = newFlatFrame(plan(hosted, native = false), images, hostCpu)
  restoreFlatStream(hostFrame, hostStream)
  for call in 0..<2:
    runFlat(hostFrame, 20)
    runFlat(hostExpected, 20)
    same(hostFrame, hostExpected)
    assert hostFrame.reason == StepError.None and hostFrame.exit == StepExit.Host, "source sealing line 226: hostFrame.reason == StepError.None and hostFrame.exit == StepExit.Host"
    assert uint64(hostFrame.hostCall) == uint64(call+3), "source sealing line 227: uint64(hostFrame.hostCall) == uint64(call+3)"
    images[0].bytes[0] = byte(100+call)
    images[1].access = if call == 0: PageAccess.ReadWrite else: PageAccess.ReadOnly
    let actualCpu = hostFrame.info
    let expectedCpu = hostExpected.info
    resumeFlatHost(hostFrame, images, actualCpu.gas, actualCpu.registers)
    resumeFlatHost(hostExpected, images, expectedCpu.gas, expectedCpu.registers)
  runFlat(hostFrame, 20)
  runFlat(hostExpected, 20)
  same(hostFrame, hostExpected)
  let hostMemory = flatMemorySnapshot(hostFrame)
  let checkedMemory = flatMemorySnapshot(hostExpected)
  for image in images:
    let left = pageImage(hostMemory, image.index).value
    let right = pageImage(checkedMemory, image.index).value
    assert left.access == right.access and left.bytes == right.bytes, "source sealing line 242: left.access == right.access and left.bytes == right.bytes"
  hostStream = takeFlatStream(hostFrame)
  frozen(hostStream, hostInfo, hostNodes, hostWork, hostNative)

  # Exact node/work boundaries demonstrate linear all-interior construction even for a long folded block.
  var noops: seq[seq[byte]] = @[]
  for index in 0..<4096: noops.add(@[2'u8])
  noops.add(@[0'u8])
  let longSource = owner(noops)
  var limits = defaultFlatLimits()
  limits.nodes = FlatNodeLimit(4098)
  limits.preparation = FlatPreparationLimit(12290)
  var longStream = prepareFlatStream(plan(longSource, limits))
  assert longStream.error == FlatError.None, "source sealing line 255: longStream.error == FlatError.None"
  var complete = takeValue(longStream)
  assert streamNodes(complete) == 4098 and streamPreparation(complete) == 12290, "source sealing line 257: streamNodes(complete) == 4098 and streamPreparation(complete) == 12290"
  assert streamSealedInfo(complete).candidates == 4097, "source sealing line 258: streamSealedInfo(complete).candidates == 4097"
  limits.nodes = FlatNodeLimit(4097)
  var nodeRefusal = prepareFlatStream(plan(longSource, limits))
  assert nodeRefusal.error == FlatError.StreamLimitExceeded, "source sealing line 261: nodeRefusal.error == FlatError.StreamLimitExceeded"
  limits.nodes = FlatNodeLimit(4098)
  limits.preparation = FlatPreparationLimit(12289)
  var workRefusal = prepareFlatStream(plan(longSource, limits))
  assert workRefusal.error == FlatError.PreparationLimitExceeded, "source sealing line 265: workRefusal.error == FlatError.PreparationLimitExceeded"

  # Unreachable blocks consume deterministic native publication capacity, then remain complete checked fallback.
  var many: seq[seq[byte]] = @[]
  for index in 0..<1100:
    for operation in 0..<4: many.add(@[100'u8, 16, 1])
    many.add(@[0'u8])
  let crowded = owner(many)
  let crowdedPlan = plan(crowded)
  var crowdedResult = prepareFlatStream(crowdedPlan)
  assert crowdedResult.error == FlatError.None, "source sealing line 275: crowdedResult.error == FlatError.None"
  var crowdedStream = takeValue(crowdedResult)
  let occupancy = streamSealedInfo(crowdedStream)
  assert occupancy.capacityDeferred > 0 and occupancy.nativeEntries > 0, "source sealing line 278: occupancy.capacityDeferred > 0 and occupancy.nativeEntries > 0"
  let saturated = streamNativeStatistics(crowdedStream)
  when defined(pvmX86Jit): assert saturated[0] == 1024, "source sealing line 280: saturated[0] == 1024"
  else: assert saturated[0] == 1023, "source sealing line 281: saturated[0] == 1023"
  let lateCpu = MachineInfo(pc: CodeAddress(1099*13), gas: MachineGas(10000))
  var late = newFlatFrame(crowdedPlan, [], lateCpu)
  var lateChecked = newFlatFrame(plan(crowded, native = false), [], lateCpu)
  restoreFlatStream(late, crowdedStream)
  runFlat(late, 100)
  runFlat(lateChecked, 100)
  same(late, lateChecked)
  crowdedStream = takeFlatStream(late)
  assert streamNativeStatistics(crowdedStream) == saturated, "source sealing line 290: streamNativeStatistics(crowdedStream) == saturated"

  # Large native bodies exhaust the unchanged byte arena before the physical-publication ceiling.
  var wide: seq[seq[byte]] = @[]
  var literal = @[149'u8]
  for operand in 0..<24: literal.add(255'u8)
  for blockIndex in 0..<1020:
    for operation in 0..<64: wide.add(literal)
    wide.add(@[0'u8])
  let widePlan = plan(owner(wide))
  var byteResult = prepareFlatStream(widePlan)
  assert byteResult.error == FlatError.None, "source sealing line 301: byteResult.error == FlatError.None"
  var byteStream = takeValue(byteResult)
  let bytesUsed = streamNativeStatistics(byteStream)
  assert bytesUsed[0] > 0 and bytesUsed[0] < 1023 and bytesUsed[3] <= 1048576, "source sealing line 304: bytesUsed[0] > 0 and bytesUsed[0] < 1023 and bytesUsed[3] <= 1048576"
  assert streamSealedInfo(byteStream).capacityDeferred > 0, "source sealing line 305: streamSealedInfo(byteStream).capacityDeferred > 0"

  # Unsupported source remains checked even beyond the native coordinate ceiling, independently of code bytes.
  var traps: seq[seq[byte]] = @[]
  for index in 0..<132000: traps.add(@[0'u8])
  var mapResult = prepareFlatStream(plan(owner(traps)))
  assert mapResult.error == FlatError.None, "source sealing line 311: mapResult.error == FlatError.None"
  var mapStream = takeValue(mapResult)
  let mapInfo = streamSealedInfo(mapStream)
  assert mapInfo.checkedEntries == 132000 and mapInfo.capacityDeferred == 0, "source sealing line 314: mapInfo.checkedEntries == 132000 and mapInfo.capacityDeferred == 0"
  assert mapInfo.nativeEntries == 0 and streamNativeStatistics(mapStream)[0] == 0, "source sealing line 315: mapInfo.nativeEntries == 0 and streamNativeStatistics(mapStream)[0] == 0"

  # Otherwise eligible sites after that same coordinate ceiling are explicitly deferred rather than unsupported.
  for operation in 0..<4: traps.add(@[100'u8, 16, 1])
  traps.add(@[0'u8])
  var mappedResult = prepareFlatStream(plan(owner(traps)))
  assert mappedResult.error == FlatError.None, "source sealing line 321: mappedResult.error == FlatError.None"
  var mappedStream = takeValue(mappedResult)
  assert streamSealedInfo(mappedStream).capacityDeferred == 1, "source sealing line 323: streamSealedInfo(mappedStream).capacityDeferred == 1"
  assert streamSealedInfo(mappedStream).checkedEntries == 132004, "source sealing line 324: streamSealedInfo(mappedStream).checkedEntries == 132004"

  when defined(pvmArm64Jit) and not defined(pvmX86Jit) and defined(pvmSourceSealingReceipt):
    # Review P2: long narrow-read spans exceed the real emitter's size bound even though their opcode/count floor passes.
    for reads in [33, 64]:
      let ordinary = narrowReadClass(0, reads)
      let saturated = narrowReadClass(132000, reads)
      assert ordinary == 0 and saturated == 0,
        "ARM oversized narrow-read policy: reads=" & $reads & " ordinary=" & $ordinary &
        " over-map=" & $saturated
    let acceptedOrdinary = narrowReadClass(0, 32)
    let acceptedOverMap = narrowReadClass(132000, 32)
    assert acceptedOrdinary == 1 and acceptedOverMap == 2,
      "ARM accepted narrow-read neighbor: ordinary=" & $acceptedOrdinary & " over-map=" & $acceptedOverMap

  # Construction cannot query an external memo; only attempted unpaid entries can add its containing price.
  let priced = owner([@[0'u8], @[100'u8, 16, 1], @[100'u8, 16, 2], @[0'u8]])
  let pricedPlan = plan(priced)
  var prices = newGasMemo(priced, GasMemoLimits(bytes: GasMemoByteLimit(1024),
      cycles: GasCycleLimit(100000)))
  assert prices.error == GasMemoError.None, "source sealing line 331: prices.error == GasMemoError.None"
  let memo = prices.value
  var pricesResult = prepareFlatStream(pricedPlan)
  assert pricesResult.error == FlatError.None, "source sealing line 334: pricesResult.error == FlatError.None"
  var pricesStream = takeValue(pricesResult)
  assert gasMemoInfo(memo).value.pricedBlocks == 0, "source sealing line 336: gasMemoInfo(memo).value.pricedBlocks == 0"
  for attempts in [0'u64, 1]:
    var frame = newFlatFrame(pricedPlan, [], MachineInfo(gas: MachineGas(10000)))
    assert selectFlatPrices(frame, default(GasPlan), memo) == StepError.None, "source sealing line 339: selectFlatPrices(frame, default(GasPlan), memo) == StepError.None"
    restoreFlatStream(frame, pricesStream)
    runFlat(frame, attempts)
    assert gasMemoInfo(memo).value.pricedBlocks == attempts, "source sealing line 342: gasMemoInfo(memo).value.pricedBlocks == attempts"
    pricesStream = takeFlatStream(frame)
  var paidFrame = newFlatFrame(pricedPlan, [], MachineInfo(pc: CodeAddress(1),
    gas: MachineGas(10000), blockCharged: true))
  assert selectFlatPrices(paidFrame, default(GasPlan), memo) == StepError.None, "source sealing line 346: selectFlatPrices(paidFrame, default(GasPlan), memo) == StepError.None"
  restoreFlatStream(paidFrame, pricesStream)
  runFlat(paidFrame, 10)
  assert gasMemoInfo(memo).value.pricedBlocks == 1, "source sealing line 349: gasMemoInfo(memo).value.pricedBlocks == 1"

  # A locally refused source price is deferred until unpaid attempted entry, including an interior entry.
  let cyclePlan = plan(pure, cycles = GasCycleLimit(0))
  var cycleResult = prepareFlatStream(cyclePlan)
  assert cycleResult.error == FlatError.None, "source sealing line 354: cycleResult.error == FlatError.None"
  var cycleStream = takeValue(cycleResult)
  for paid in [false, true]:
    let cpu = MachineInfo(pc: CodeAddress(3), gas: MachineGas(10000), blockCharged: paid)
    var frame = newFlatFrame(cyclePlan, [], cpu)
    var expected = newFlatFrame(plan(pure, cycles = GasCycleLimit(0), native = false), [], cpu)
    restoreFlatStream(frame, cycleStream)
    runFlat(frame, 100)
    runFlat(expected, 100)
    same(frame, expected)
    cycleStream = takeFlatStream(frame)

  let completePrices = newGasPlan(pure, GasPlanLimits(bytes: GasPlanByteLimit(4096),
    blocks: GasPlanBlockLimit(100), cycles: GasCycleLimit(100000)))
  assert completePrices.error == GasPlanError.None, "source sealing line 368: completePrices.error == GasPlanError.None"
  for selection in [1, 2]:
    # A caller's selected pricing authority may succeed even though this plan's private direct price refused.
    let selectedMemo = newGasMemo(pure, GasMemoLimits(bytes: GasMemoByteLimit(4096),
      cycles: GasCycleLimit(100000))).value
    let cpu = MachineInfo(pc: CodeAddress(3), gas: MachineGas(10000))
    var frame = newFlatFrame(cyclePlan, [], cpu)
    var expected = newFlatFrame(plan(pure, native = false), [], cpu)
    let selectedPlan = if selection == 1: completePrices.value else: default(GasPlan)
    let selected = if selection == 2: selectedMemo else: default(GasMemo)
    assert selectFlatPrices(frame, selectedPlan, selected) == StepError.None, "source sealing line 378: selectFlatPrices(frame, selectedPlan, selected) == StepError.None"
    assert selectFlatPrices(expected, selectedPlan, selected) == StepError.None, "source sealing line 379: selectFlatPrices(expected, selectedPlan, selected) == StepError.None"
    restoreFlatStream(frame, cycleStream)
    runFlat(frame, 100)
    runFlat(expected, 100)
    same(frame, expected)
    assert frame.reason == StepError.None, "source sealing line 384: frame.reason == StepError.None"
    cycleStream = takeFlatStream(frame)

stdout.writeLine("PVM_SOURCE_SEALING_OK")
