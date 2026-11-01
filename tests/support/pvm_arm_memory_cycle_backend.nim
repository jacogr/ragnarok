# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Literal backend controls for the same-owner ARM memory cycle and its refusal paths.

import std/assertions
import ../../src/pvm/[program, machine]
import ../../src/pvm/internal/arm64_jit

type CycleCaseResult = object ## Copied execution output keeps borrowed context/storage local to one call.
  destination: uint32
  registers: RegisterFile
  state: array[14, uint64]
  bytes: array[16, byte]

proc pureBlocks(slots: RegisterSlots): array[3, ArmRegionBlock] =
  ## Build an unrelated two-block pure loop in disjoint stream slots for coexistence checks.
  result = default(array[3, ArmRegionBlock])
  # Two active blocks leave the third metadata lane inactive and preserve its sentinel checks.
  for index in 0..<2:
    var body = default(ArmBlock)
    emitArmOperation(body, 149, slots, 1)
    let next = if index == 0: 102'u32 else: 101'u32
    emitArmBranch(body, 81, slots, 65535, 99, next)
    result[index] = ArmRegionBlock(header: (if index == 0: 101'u32 else: 102'u32),
        span: 2, operations: 2, price: 1, yes: 99, no: next, body: move(body))

proc runPure(jit: ArmJit): uint64 =
  ## Execute exactly three pure block visits and return the copied outer-call count.
  var registers = default(RegisterFile)
  var state = [12'u64, 6'u64, 0'u64, 0'u64, 0'u64]
  let destination = callArmRegion(jit, registers, state)
  assert destination == 102
  assert state == [9'u64, 0'u64, 2'u64, 1'u64, 0'u64]
  assert registers[0] == RegisterValue(3)
  result = jit.calls

proc cycleDirty(dirtySource: Program): ArmRegionBlock =
  ## Lower the five fixed operations from the decoded literal owner.
  var dirty = newArmRegionBody()
  let first = instruction(dirtySource, CodeAddress(0))
  let store = instruction(dirtySource, CodeAddress(3))
  let incrementBase = instruction(dirtySource, CodeAddress(6))
  let incrementShift = instruction(dirtySource, CodeAddress(9))
  let dirtyBranch = instruction(dirtySource, CodeAddress(12))
  for decoded in [first, store, incrementBase, incrementShift, dirtyBranch]:
    assert decoded.error == ProgramError.None
  assert first.value.opcode == 198 and store.value.opcode == 120 and
      incrementBase.value.opcode == 149 and incrementShift.value.opcode == 149 and
      dirtyBranch.value.opcode == 171
  emitArmOperation(dirty, 198, instructionRegisters(first), uint64(first.value.x))
  emitArmDirtyRegionByteStore(dirty, instructionRegisters(store).aIndex)
  emitArmOperation(dirty, 149, instructionRegisters(incrementBase),
      uint64(incrementBase.value.x))
  emitArmOperation(dirty, 149, instructionRegisters(incrementShift),
      uint64(incrementShift.value.x))
  emitArmBranch(dirty, 171, instructionRegisters(dirtyBranch), 0, 20, 30)
  ArmRegionBlock(header: 20, span: 5, operations: 5,
      yes: 20, no: 30, price: 5, body: move(dirty))

proc cycleRead(tailSource: Program): ArmReadSpan =
  ## Reuse the same decoded read IR for the linked child and resident body.
  var read = default(ArmReadSpan)
  let directRead = instruction(tailSource, CodeAddress(0))
  let tailIncrement = instruction(tailSource, CodeAddress(6))
  let tailBranch = instruction(tailSource, CodeAddress(9))
  for decoded in [directRead, tailIncrement, tailBranch]: assert decoded.error == ProgramError.None
  assert directRead.value.opcode == 57 and tailIncrement.value.opcode == 149 and
      tailBranch.value.opcode == 173
  emitArmDirectRead(read, instructionRegisters(directRead), 65544, 57)
  emitArmReadArithmetic(read, 149, instructionRegisters(tailIncrement),
      uint64(tailIncrement.value.x))
  emitArmReadBranch(read, 173, instructionRegisters(tailBranch), 0, 10, 40)
  move(read)

proc publishChildren(jit: ArmJit, dirtySource, tailSource: Program,
    word = default(ArmDirtyWordShape)) =
  ## Publish the fixed dirty and direct-read children from separately decoded owners.
  let store = instruction(dirtySource, CodeAddress(3))
  assert store.error == ProgramError.None and store.value.opcode == 120
  var dirtyItem = cycleDirty(dirtySource)
  assert publishArmDirtyLoop(jit, move(dirtyItem), instructionRegisters(store).bIndex, 0, word)
  let read = cycleRead(tailSource)
  var tailWords = armReadInstructions(read, 32, true)
  assert publishArmEntry(jit, 31, 32, 3, tailWords)

proc cyclePrefix(prefixSource: Program): ArmBlock =
  ## Build three literal pure operations and an optional write-only slot-12 assignment.
  result = default(ArmBlock)
  for pc in [0'u64, 3'u64, 6'u64]:
    let decoded = instruction(prefixSource, CodeAddress(pc))
    assert decoded.error == ProgramError.None and decoded.value.opcode == 149
    emitArmOperation(result, 149, instructionRegisters(decoded), uint64(decoded.value.x))
  let fourth = instruction(prefixSource, CodeAddress(9))
  assert fourth.error == ProgramError.None
  var ending = 9'u64
  if fourth.value.opcode == 51:
    assert instructionRegisters(fourth).destinationIndex == 12
    emitArmOperation(result, 51, instructionRegisters(fourth), uint64(fourth.value.x))
    ending = 12
  let branch = instruction(prefixSource, CodeAddress(ending))
  let stop = instruction(prefixSource, CodeAddress(ending+1))
  assert branch.error == ProgramError.None and branch.value.opcode == 1 and
      stop.error == ProgramError.None and stop.value.opcode == 0

proc cycleBlock(prefix: sink ArmBlock): ArmMemoryCycleBlock =
  ## Bind the small literal graph to source spans/prices distinct from its native operation counts.
  ArmMemoryCycleBlock(prefixHeader: 10, dirtyHeader: 20, tailHeader: 30,
      tailEntry: 31, other: 40, prefixSpan: 4, tailSpan: 4,
      prefixOperations: 3, tailOperations: 3, prefixPrice: 7, tailPrice: 11,
      prefixBody: move(prefix))

proc initialRegisters(): RegisterFile =
  ## Initialize disjoint source/base/shift/bound roles and preserve meaningful high-bit values.
  result = default(RegisterFile)
  result[0] = RegisterValue(65536)
  result[1] = RegisterValue(0x1234)
  result[2] = RegisterValue(0xa5)
  result[3] = RegisterValue(65538)
  result[7] = RegisterValue(65540)

proc initialCaseRegisters(wordBound, writeOnly: bool): RegisterFile =
  result = initialRegisters()
  if wordBound: result[3] = RegisterValue(65544)
  if writeOnly: result[12] = RegisterValue(0xdeadbeef01234567'u64)

proc runCase(jit: ArmJit, gas, attempts, readExtent: uint64,
    dirtyWordCount = 16384, wordBound = false,
    writeOnly = false): CycleCaseResult =
  ## Keep fresh byte storage, descriptors, bitmap and accounting on this call's stack.
  var bytes = default(array[16, byte])
  var descriptors = default(array[3, array[3, uint64]])
  descriptors[1] = [65536'u64, readExtent, cast[uint64](addr bytes[0])]
  var dirtyWords = newSeq[uint64](dirtyWordCount)
  # An empty bitmap must refuse before any native byte mutation.
  if dirtyWords.len > 0: dirtyWords[0] = 1'u64 shl 16
  var registers = initialCaseRegisters(wordBound, writeOnly)
  var state = default(array[14, uint64])
  state[0] = gas
  state[1] = attempts
  state[13] = uint64(high(uint32))
  let destination = callArmMemoryCycle(jit, registers, descriptors, dirtyWords, state)
  CycleCaseResult(destination: destination, registers: registers, state: state, bytes: bytes)

proc oversizedPrefix(slots: RegisterSlots): ArmBlock =
  ## Emit a bounded literal prefix that exceeds the existing executable-image word limit.
  result = default(ArmBlock)
  for index in 0..<300: emitArmOperation(result, 149, slots, 1)

proc oversizedBlock(prefix: sink ArmBlock): ArmMemoryCycleBlock =
  ## Offer a valid source graph whose immutable prefix is too large to publish.
  ArmMemoryCycleBlock(prefixHeader: 10, dirtyHeader: 20, tailHeader: 30,
      tailEntry: 31, other: 40, prefixSpan: 301, tailSpan: 4,
      prefixOperations: 300, tailOperations: 3, prefixPrice: 7, tailPrice: 11,
      prefixBody: move(prefix))

proc cycleWord(dirtySource: Program): ArmDirtyWordShape =
  ## Enable the four-byte lowering only for the decoded literal word fixture.
  let first = instruction(dirtySource, CodeAddress(0))
  let store = instruction(dirtySource, CodeAddress(3))
  let baseStep = instruction(dirtySource, CodeAddress(6))
  let shiftStep = instruction(dirtySource, CodeAddress(9))
  let branch = instruction(dirtySource, CodeAddress(12))
  for decoded in [first, store, baseStep, shiftStep, branch]:
    assert decoded.error == ProgramError.None
  if first.value.opcode != 198 or store.value.opcode != 120 or
      baseStep.value.opcode != 149 or shiftStep.value.opcode != 149 or
      branch.value.opcode != 171:
    return default(ArmDirtyWordShape)
  let firstSlots = instructionRegisters(first)
  let storeSlots = instructionRegisters(store)
  let baseSlots = instructionRegisters(baseStep)
  let shiftSlots = instructionRegisters(shiftStep)
  let branchSlots = instructionRegisters(branch)
  let roles = [firstSlots.aIndex, firstSlots.bIndex,
      firstSlots.destinationIndex, storeSlots.bIndex, branchSlots.bIndex]
  for i in 0..<5:
    for j in i+1..<5:
      if roles[i] == roles[j]: return default(ArmDirtyWordShape)
  if storeSlots.aIndex != firstSlots.destinationIndex or
      baseSlots.aIndex != storeSlots.bIndex or
      baseSlots.bIndex != storeSlots.bIndex or uint64(baseStep.value.x) != 1 or
      shiftSlots.aIndex != firstSlots.bIndex or
      shiftSlots.bIndex != firstSlots.bIndex or uint64(shiftStep.value.x) != 8 or
      branchSlots.aIndex != storeSlots.bIndex:
    return default(ArmDirtyWordShape)
  ArmDirtyWordShape(enabled: true, source: roles[0], shift: roles[1],
      destination: roles[2], base: roles[3], bound: roles[4])

proc residentBlock(dirtySource, prefixSource, tailSource: Program,
    word: ArmDirtyWordShape): ArmMemoryCycleBlock =
  ## Assemble one candidate from the same literal-backed builders as the linked control.
  let store = instruction(dirtySource, CodeAddress(3))
  let fourth = instruction(prefixSource, CodeAddress(9))
  assert store.error == ProgramError.None and store.value.opcode == 120
  assert fourth.error == ProgramError.None and fourth.value.opcode in {1'u8, 51'u8}
  let prefixSpan = if fourth.value.opcode == 51: 5'u32 else: 4'u32
  ArmMemoryCycleBlock(prefixHeader: 10, dirtyHeader: 20, tailHeader: 30,
      tailEntry: 31, other: 40, prefixSpan: prefixSpan, tailSpan: 4,
      prefixOperations: prefixSpan-1, tailOperations: 3,
      prefixPrice: 7, tailPrice: 11, prefixBody: cyclePrefix(prefixSource),
      dirty: cycleDirty(dirtySource),
      dirtyBaseSlot: instructionRegisters(store).bIndex,
      dirtyDisplacement: uint32(uint64(store.value.x) and 0xffffffff'u64),
      dirtyWord: word, tailRead: cycleRead(tailSource))

proc sameCase(left, right: CycleCaseResult) =
  assert left.destination == right.destination
  assert left.registers == right.registers
  assert left.state[0] == right.state[0] and left.state[1] == right.state[1]
  for index in 8..<14: assert left.state[index] == right.state[index]
  assert left.bytes == right.bytes

proc checkArmMemoryCycleBackend*(dirtySource, prefixSource, tailSource: Program): uint64 =
  ## Count independently checked backend boundaries for these three immutable literal owners.
  result = 0
  let pureDecoded = instruction(dirtySource, CodeAddress(6))
  let prefixDecoded = instruction(prefixSource, CodeAddress(0))
  let tailDecoded = instruction(tailSource, CodeAddress(0))
  assert pureDecoded.error == ProgramError.None and pureDecoded.value.opcode == 149
  assert prefixDecoded.error == ProgramError.None and prefixDecoded.value.opcode == 149
  assert tailDecoded.error == ProgramError.None and tailDecoded.value.opcode == 57
  let pureSlots = instructionRegisters(pureDecoded)

  when defined(pvmArm64JitRefuse):
    # OS refusal must retain zero publications and make driver refusal permanent.
    when defined(pvmArmDirtyLoopOwnerReceipt):
      let destroyed = armDirtyLoopArenaDestroyed()
    block:
      let refused = newArmJit()
      assert armEntry(refused, 101, 128) == 0
      var blocks = pureBlocks(pureSlots)
      assert not publishArmRegion(refused, blocks, 2)
      assert armRegionStatus(refused) == 1 and armMemoryCycleStatus(refused) == 0
      assert refused.fragments == 0 and refused.codeBytes == 0 and refused.calls == 0
      assert armEntry(refused, 101, 128) == 1
      assert not publishArmMemoryCycle(refused, default(ArmMemoryCycleBlock))
      assert armMemoryCycleStatus(refused) == 1
      assert not publishArmMemoryCycle(refused, default(ArmMemoryCycleBlock))
      assert refused.fragments == 0 and refused.codeBytes == 0
    when defined(pvmArmDirtyLoopOwnerReceipt):
      assert armDirtyLoopArenaDestroyed() == destroyed
    result = 1
  else:
    # Real publication and execution are required before checking fallback and capacity.
    let jit = newArmJit()
    assert armEntry(jit, 0, 64) == 0 and armEntry(jit, 101, 128) == 0
    var blocks = pureBlocks(pureSlots)
    assert publishArmRegion(jit, blocks, 2)
    assert armRegionStatus(jit) == 2 and armRegionCount(jit) == 2
    assert armRegionChargeMatches(jit, 0, 101, 2, 1) and
        armRegionChargeMatches(jit, 1, 102, 2, 1)
    let beforePureCalls = runPure(jit)
    let beforePure = armRegionStatistics(jit)
    inc result

    publishChildren(jit, dirtySource, tailSource)
    assert armDirtyLoopStatus(jit) == 2
    inc result
    assert armEntry(jit, 31, 64) >= 2
    inc result
    var prefix = cyclePrefix(prefixSource)
    var cycle = cycleBlock(move(prefix))
    assert publishArmMemoryCycle(jit, move(cycle))
    assert armMemoryCycleStatus(jit) == 2
    assert armMemoryCycleChargeMatches(jit, 0, 10, 4, 7) and
        armMemoryCycleChargeMatches(jit, 1, 30, 4, 11)
    inc result
    let afterPureCalls = runPure(jit)
    assert armRegionStatistics(jit) == [beforePure[0]+1, beforePure[1]+3]
    assert afterPureCalls == beforePureCalls+1
    assert armMemoryCycleStatistics(jit) == [0'u64, 0, 0, 0, 0, 0]
    inc result

    let complete = runCase(jit, 1000, 1000, 9)
    assert complete.destination == 40 and complete.state[0] == 944 and
        complete.state[1] == 964 and complete.state[8] == 2 and
        complete.state[9] == 2 and complete.state[10] == 4 and
        complete.state[12] == 2 and complete.state[13] == 30
    assert complete.registers[0] == RegisterValue(65540) and
        complete.registers[5] == RegisterValue(6) and
        complete.bytes[0] == 0x34 and complete.bytes[1] == 0x35
    inc result
    # A zero attempt budget cannot consume gas, change registers or add completed child work.
    let beforeZero = armMemoryCycleStatistics(jit)
    let zero = runCase(jit, 0, 0, 9)
    assert zero.destination == 10 and zero.registers == initialRegisters() and
        zero.state[13] == uint64(high(uint32))
    let afterZero = armMemoryCycleStatistics(jit)
    assert afterZero[0] == beforeZero[0]+1
    for index in 1..<6: assert afterZero[index] == beforeZero[index]
    inc result
    let noGas = runCase(jit, 6, 100, 9)
    assert noGas.destination == 10 and noGas.registers == initialRegisters() and
        noGas.state[1] == 100
    inc result
    let partial = runCase(jit, 100, 3, 9)
    assert partial.destination == 10 and partial.registers == initialRegisters() and
        partial.state[0] == 100
    inc result
    let dirtyGuard = runCase(jit, 7, 100, 9)
    assert dirtyGuard.destination == 20 and dirtyGuard.state[8] == 1 and
        dirtyGuard.state[10] == 0 and dirtyGuard.state[12] == 1 and
        dirtyGuard.state[13] == 10
    inc result
    # Earlier dirty bytes survive a read guard while its unstarted tail price/span is refunded.
    let readRefusal = runCase(jit, 1000, 1000, 1)
    assert readRefusal.destination == 30 and readRefusal.state[8] == 1 and
        readRefusal.state[9] == 0 and readRefusal.state[10] == 2 and
        readRefusal.state[0] == 983 and readRefusal.state[1] == 986 and
        readRefusal.state[13] == 20 and readRefusal.bytes[0] == 0x34 and
        readRefusal.bytes[1] == 0x35
    inc result
    let emptyDescriptor = runCase(jit, 1000, 1000, 0)
    assert emptyDescriptor.destination == 20 and emptyDescriptor.state[8] == 1 and
        emptyDescriptor.state[9] == 0 and emptyDescriptor.state[10] == 0 and
        emptyDescriptor.state[0] == 993 and emptyDescriptor.state[1] == 996 and
        emptyDescriptor.bytes == default(array[16, byte])
    inc result
    let emptyBitmap = runCase(jit, 1000, 1000, 9, 0)
    assert emptyBitmap.destination == 20 and emptyBitmap.state[0] == 993 and
        emptyBitmap.state[1] == 996 and emptyBitmap.state[8] == 1 and
        emptyBitmap.state[9] == 0 and emptyBitmap.state[10] == 0 and
        emptyBitmap.state[12] == 1 and
        emptyBitmap.bytes == default(array[16, byte])
    inc result
    let beforePureAgain = armRegionStatistics(jit)
    let beforeCycleAgain = armMemoryCycleStatistics(jit)
    discard runPure(jit)
    assert armRegionStatistics(jit) == [beforePureAgain[0]+1, beforePureAgain[1]+3]
    assert armMemoryCycleStatistics(jit) == beforeCycleAgain
    inc result

    # A failed relocation expectation cannot replace an already callable driver.
    let before = armEntry(jit, 10, 64)
    var rejected: seq[uint32] = @[0xd503201f'u32]
    assert not publishArmEntry(jit, 10, 0, 0, rejected, expectedStart = 0)
    assert armEntry(jit, 10, 64) == before
    assert runCase(jit, 1000, 1000, 9).destination == 40
    inc result
    # Exhaust remaining bytes through real publication and keep existing driver code callable.
    var filled = 0
    for offset in 50'u32..<1000'u32:
      discard armEntry(jit, offset, 1024)
      var filler = newSeq[uint32](1023)
      for index in 0..<filler.len: filler[index] = 0xd503201f'u32
      if not publishArmEntry(jit, offset, 0, 0, filler): break
      inc filled
    assert filled > 0 and jit.codeBytes <= 1048576 and
        runCase(jit, 1000, 1000, 9).destination == 40
    inc result

    when defined(pvmArmDirtyLoopOwnerReceipt):
      let beforeDestroy = armDirtyLoopArenaDestroyed()
    # One local owner releases its arena exactly once after its last reference.
    block:
      let disposable = newArmJit()
      assert armEntry(disposable, 0, 64) == 0
      var oneWord: seq[uint32] = @[0xd503201f'u32]
      assert publishArmEntry(disposable, 0, 0, 1, oneWord)
      when defined(pvmArmDirtyLoopOwnerReceipt):
        assert armDirtyLoopArenaDestroyed() == beforeDestroy
    when defined(pvmArmDirtyLoopOwnerReceipt):
      assert armDirtyLoopArenaDestroyed() == beforeDestroy+1
    inc result

    # Ordinary-slot exhaustion is sticky while the independent pure-region reservation stays intact.
    block:
      let full = newArmJit()
      assert not publishArmMemoryCycle(full, default(ArmMemoryCycleBlock))
      assert armMemoryCycleStatus(full) == 0
      assert armEntry(full, 0, 1024) == 0
      for offset in 0'u32..<1023'u32:
        var oneWord: seq[uint32] = @[0xd503201f'u32]
        assert publishArmEntry(full, offset, 0, 1, oneWord)
      assert full.fragments == 1023 and full.codeBytes > 0
      let bytes = full.codeBytes
      assert not publishArmMemoryCycle(full, default(ArmMemoryCycleBlock))
      assert armMemoryCycleStatus(full) == 1 and full.codeBytes == bytes
      assert not publishArmMemoryCycle(full, default(ArmMemoryCycleBlock))
      assert full.fragments == 1023 and full.codeBytes == bytes
    inc result

    # A ready but oversized image must stop recompiling and retain all earlier source/code capabilities.
    block:
      let oversized = newArmJit()
      assert armEntry(oversized, 0, 64) == 0
      var primary: seq[uint32] = @[0x52800020'u32]
      assert publishArmEntry(oversized, 0, 77, 1, primary)
      publishChildren(oversized, dirtySource, tailSource)
      var large = oversizedPrefix(instructionRegisters(prefixDecoded))
      assert armInstructions(large).len >= 1024
      var largeCycle = oversizedBlock(move(large))
      let primaryCode = armEntry(oversized, 0, 64)
      let dirtyCode = armEntry(oversized, 20, 64)
      let tailCode = armEntry(oversized, 31, 64)
      let beforeBytes = oversized.codeBytes
      let beforeFragments = oversized.fragments
      assert not publishArmMemoryCycle(oversized, move(largeCycle))
      assert armMemoryCycleStatus(oversized) == 1 and
          oversized.codeBytes == beforeBytes and oversized.fragments == beforeFragments and
          armEntry(oversized, 10, 64) == 0
      assert armEntry(oversized, 0, 64) == primaryCode and
          armEntry(oversized, 20, 64) == dirtyCode and
          armEntry(oversized, 31, 64) == tailCode and armDirtyLoopStatus(oversized) == 2
      var registers = default(RegisterFile)
      assert callArmEntry(oversized, 0, registers) == 77 and
          registers == default(RegisterFile)
      var repeated = oversizedPrefix(instructionRegisters(prefixDecoded))
      var repeatedCycle = oversizedBlock(move(repeated))
      assert not publishArmMemoryCycle(oversized, move(repeatedCycle))
      assert armMemoryCycleStatus(oversized) == 1 and
          oversized.codeBytes == beforeBytes and oversized.fragments == beforeFragments
    inc result

proc checkArmResidentMemoryCycleBackend*(dirtySource, prefixSource,
    tailSource: Program): uint64 =
  ## Check one literal graph with a resident driver; callers can supply word and slot-12 variants.
  result = 0
  let word = cycleWord(dirtySource)
  let fourth = instruction(prefixSource, CodeAddress(9))
  assert fourth.error == ProgramError.None and fourth.value.opcode in {1'u8, 51'u8}
  let writeOnly = fourth.value.opcode == 51
  let wordBound = word.enabled
  let pureDecoded = instruction(dirtySource, CodeAddress(6))
  assert pureDecoded.error == ProgramError.None and pureDecoded.value.opcode == 149

  when defined(pvmArm64JitRefuse):
    block:
      let refused = newArmJit()
      assert armEntry(refused, 101, 128) == 0
      var blocks = pureBlocks(instructionRegisters(pureDecoded))
      assert not publishArmRegion(refused, blocks, 2)
      assert refused.fragments == 0 and refused.codeBytes == 0
      assert not publishArmResidentMemoryCycle(refused,
          residentBlock(dirtySource, prefixSource, tailSource, word))
      assert armMemoryCycleStatus(refused) == 0
      assert not armResidentMemoryCycleActive(refused)
      assert not publishArmMemoryCycle(refused, default(ArmMemoryCycleBlock))
      assert armMemoryCycleStatus(refused) == 1
      assert refused.fragments == 0 and refused.codeBytes == 0 and refused.calls == 0
    result = 1
  else:
    let jit = newArmJit()
    assert armEntry(jit, 0, 64) == 0 and armEntry(jit, 101, 128) == 0
    var blocks = pureBlocks(instructionRegisters(pureDecoded))
    assert publishArmRegion(jit, blocks, 2)
    assert armRegionStatus(jit) == 2
    let pureCalls = runPure(jit)
    let pureStats = armRegionStatistics(jit)
    inc result

    publishChildren(jit, dirtySource, tailSource, word)
    assert armDirtyLoopStatus(jit) == 2 and armEntry(jit, 31, 64) >= 2
    inc result
    var cycle = residentBlock(dirtySource, prefixSource, tailSource, word)
    assert publishArmResidentMemoryCycle(jit, move(cycle))
    assert armMemoryCycleStatus(jit) == 2 and armResidentMemoryCycleActive(jit)
    let span = if writeOnly: 5'u32 else: 4'u32
    assert armMemoryCycleChargeMatches(jit, 0, 10, span, 7)
    assert armMemoryCycleChargeMatches(jit, 1, 30, 4, 11)
    inc result
    assert runPure(jit) == pureCalls+1
    assert armRegionStatistics(jit) == [pureStats[0]+1, pureStats[1]+3]
    assert armMemoryCycleStatistics(jit) == [0'u64, 0, 0, 0, 0, 0]
    inc result

    let complete = runCase(jit, 1000, 1000, 9, wordBound = wordBound,
        writeOnly = writeOnly)
    assert complete.destination == 40 and complete.state[8] > 0 and
        complete.state[9] > 0 and complete.state[10] > 0 and
        complete.state[12] > 0 and complete.bytes[0] == 0x34
    if not wordBound:
      assert complete.state[0] == 944 and complete.state[1] ==
          (if writeOnly: 962'u64 else: 964'u64)
      assert complete.registers[0] == RegisterValue(65540) and
          complete.registers[5] == RegisterValue(6) and complete.bytes[1] == 0x35
    else:
      assert complete.state[11] > 0
    inc result

    let initial = initialCaseRegisters(wordBound, writeOnly)
    let beforeZero = armMemoryCycleStatistics(jit)
    let zero = runCase(jit, 0, 0, 9, wordBound = wordBound, writeOnly = writeOnly)
    assert zero.destination == 10 and zero.registers == initial and
        zero.state[0] == 0 and zero.state[1] == 0 and
        zero.state[13] == uint64(high(uint32))
    let afterZero = armMemoryCycleStatistics(jit)
    assert afterZero[0] == beforeZero[0]+1
    for index in 1..<6: assert afterZero[index] == beforeZero[index]
    inc result
    let noGas = runCase(jit, 6, 100, 9, wordBound = wordBound,
        writeOnly = writeOnly)
    assert noGas.destination == 10 and noGas.registers == initial and
        noGas.state[0] == 6 and noGas.state[1] == 100
    inc result
    let partial = runCase(jit, 100, 3, 9, wordBound = wordBound,
        writeOnly = writeOnly)
    assert partial.destination == 10 and partial.registers == initial and
        partial.state[0] == 100 and partial.state[1] == 3
    inc result
    let dirtyGuard = runCase(jit, 7, 100, 9, wordBound = wordBound,
        writeOnly = writeOnly)
    assert dirtyGuard.destination == 20 and dirtyGuard.state[8] == 1 and
        dirtyGuard.state[10] == 0 and dirtyGuard.state[12] == 1 and
        dirtyGuard.state[13] == 10
    inc result

    let readRefusal = runCase(jit, 1000, 1000, 1, wordBound = wordBound,
        writeOnly = writeOnly)
    assert readRefusal.destination == 30 and readRefusal.state[8] > 0 and
        readRefusal.state[9] == 0 and readRefusal.state[10] > 0 and
        readRefusal.state[13] == 20 and readRefusal.bytes[0] == 0x34
    if not wordBound:
      assert readRefusal.state[0] == 983 and readRefusal.state[1] ==
          (if writeOnly: 985'u64 else: 986'u64)
      assert readRefusal.bytes[1] == 0x35
    inc result
    let emptyDescriptor = runCase(jit, 1000, 1000, 0,
        wordBound = wordBound, writeOnly = writeOnly)
    assert emptyDescriptor.destination == 20 and emptyDescriptor.state[8] == 1 and
        emptyDescriptor.state[9] == 0 and emptyDescriptor.state[10] == 0 and
        emptyDescriptor.state[0] == 993 and emptyDescriptor.state[1] ==
            (if writeOnly: 995'u64 else: 996'u64) and
        emptyDescriptor.bytes == default(array[16, byte])
    inc result
    let emptyBitmap = runCase(jit, 1000, 1000, 9, 0,
        wordBound = wordBound, writeOnly = writeOnly)
    assert emptyBitmap.destination == 20 and emptyBitmap.state[8] == 1 and
        emptyBitmap.state[9] == 0 and emptyBitmap.state[10] == 0 and
        emptyBitmap.bytes == default(array[16, byte])
    inc result
    let beforePureAgain = armRegionStatistics(jit)
    let beforeCycleAgain = armMemoryCycleStatistics(jit)
    discard runPure(jit)
    assert armRegionStatistics(jit) == [beforePureAgain[0]+1, beforePureAgain[1]+3]
    assert armMemoryCycleStatistics(jit) == beforeCycleAgain
    inc result

    if writeOnly:
      assert complete.registers[12] == RegisterValue(42) and
          dirtyGuard.registers[12] == RegisterValue(42) and
          readRefusal.registers[12] == RegisterValue(42)
      assert zero.registers[12] == RegisterValue(0xdeadbeef01234567'u64)
      inc result
    if wordBound:
      assert not writeOnly
      let linked = newArmJit()
      assert armEntry(linked, 0, 64) == 0
      publishChildren(linked, dirtySource, tailSource, word)
      var linkedCycle = cycleBlock(cyclePrefix(prefixSource))
      assert publishArmMemoryCycle(linked, move(linkedCycle))
      assert not armResidentMemoryCycleActive(linked)
      let linkedComplete = runCase(linked, 1000, 1000, 9, wordBound = true)
      sameCase(complete, linkedComplete)
      let linkedRefusal = runCase(linked, 1000, 1000, 1, wordBound = true)
      sameCase(readRefusal, linkedRefusal)
      assert complete.state[11] > 0 and readRefusal.state[11] > 0
      inc result

    # An overlarge resident image declines without consuming the linked driver's slot.
    block:
      let fallback = newArmJit()
      assert armEntry(fallback, 0, 64) == 0
      publishChildren(fallback, dirtySource, tailSource, word)
      var large = newArmRegionBody()
      let prefixFirst = instruction(prefixSource, CodeAddress(0))
      assert prefixFirst.error == ProgramError.None and prefixFirst.value.opcode == 149
      for index in 0..<400:
        emitArmOperation(large, 149, instructionRegisters(prefixFirst),
            uint64(prefixFirst.value.x))
      assert armInstructions(large).len >= 800 and armInstructions(large).len < 1024
      var oversized = residentBlock(dirtySource, prefixSource, tailSource, word)
      oversized.prefixBody = move(large)
      oversized.prefixSpan = 401
      oversized.prefixOperations = 400
      let bytes = fallback.codeBytes
      let fragments = fallback.fragments
      assert not publishArmResidentMemoryCycle(fallback, oversized)
      assert armMemoryCycleStatus(fallback) == 0 and
          not armResidentMemoryCycleActive(fallback) and
          fallback.codeBytes == bytes and fallback.fragments == fragments
      assert publishArmMemoryCycle(fallback, move(oversized))
      assert armMemoryCycleStatus(fallback) == 2 and
          not armResidentMemoryCycleActive(fallback) and
          fallback.fragments == fragments+1
    inc result

    # A disposable resident owner releases its executable arena once.
    when defined(pvmArmDirtyLoopOwnerReceipt):
      let beforeDestroy = armDirtyLoopArenaDestroyed()
    block:
      let owned = newArmJit()
      assert armEntry(owned, 0, 64) == 0
      publishChildren(owned, dirtySource, tailSource, word)
      var ownedCycle = residentBlock(dirtySource, prefixSource, tailSource, word)
      assert publishArmResidentMemoryCycle(owned, move(ownedCycle))
      assert armResidentMemoryCycleActive(owned)
    when defined(pvmArmDirtyLoopOwnerReceipt):
      assert armDirtyLoopArenaDestroyed() == beforeDestroy+1
    inc result
