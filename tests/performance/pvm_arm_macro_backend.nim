# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Source-derived ARM macro backend literals, called by the main witness.
import std/[assertions, syncio]
import ../../src/codec/natural
import ../../src/pvm/[program, machine]
import ../../src/pvm/internal/arm64_jit

proc checkEmpty(): int =
  let empty = newArmJit()
  assert armMacroStatus(empty) == 0
  let absent = armMacroChildRecord(empty, 0)
  assert absent.code == 0 and absent.operations == 0 and absent.ending == 0
  assert not armMacroProbeReady(empty)
  for probe in 1..6: assert not armMacroProbeReady(empty)
  assert armMacroProbeReady(empty)
  assert armMacroProbeReady(empty)
  refuseArmMacro(empty)
  assert armMacroStatus(empty) == 1 and not armMacroProbeReady(empty)
  result = 1

proc literalOwner(parts: openArray[seq[byte]]): Program =
  ## Decode a separate literal source owner and its exact instruction mask.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    starts.add(code.len)
    for value in part: code.add(value)
  var bytes: seq[byte] = @[]
  let zero = encode(JamNatural(0))
  for index in 0..<zero.len: bytes.add(zero.bytes[index])
  bytes.add(0'u8)
  let length = encode(JamNatural(uint64(code.len)))
  for index in 0..<length.len: bytes.add(length.bytes[index])
  for value in code: bytes.add(value)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for value in mask: bytes.add(value)
  let decoded = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(65536),
      JumpCountLimit(1024))
  assert decoded.error == ProgramError.None
  decoded.value

let dirtySource = literalOwner([@[198'u8, 0x41, 2], @[120'u8, 0x02, 0],
    @[149'u8, 0x00, 1], @[149'u8, 0x11, 1],
    @[171'u8, 0x30, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
let prefixSource = literalOwner([@[149'u8, 0x55, 1], @[149'u8, 0x55, 1],
    @[149'u8, 0x55, 1], @[1'u8], @[0'u8]])
let tailSource = literalOwner([@[57'u8, 6, 0, 0, 1, 0], @[149'u8, 0x33, 2],
    @[173'u8, 0x70, 0, 0, 0, 0], @[0'u8]])
let pureSource = literalOwner([@[149'u8, 0xcc, 1],
    @[81'u8, 0x1c, 42, 0], @[0'u8]])
let branchSource = literalOwner([@[88'u8, 0x4c, 0xff, 0xff, 0xff, 0xff, 0], @[0'u8]])
let readSource = literalOwner([@[130'u8, 0x06, 8, 0, 0, 0], @[0'u8]])

proc dirtyBody(): ArmRegionBlock =
  ## Five independently decoded operations include one byte store and a real branch.
  var body = newArmRegionBody()
  let first = instruction(dirtySource, CodeAddress(0))
  let store = instruction(dirtySource, CodeAddress(3))
  let baseStep = instruction(dirtySource, CodeAddress(6))
  let shiftStep = instruction(dirtySource, CodeAddress(9))
  let branch = instruction(dirtySource, CodeAddress(12))
  for decoded in [first, store, baseStep, shiftStep, branch]:
    assert decoded.error == ProgramError.None
  emitArmOperation(body, 198, instructionRegisters(first), uint64(first.value.x))
  emitArmDirtyRegionByteStore(body, instructionRegisters(store).aIndex)
  emitArmOperation(body, 149, instructionRegisters(baseStep), uint64(baseStep.value.x))
  emitArmOperation(body, 149, instructionRegisters(shiftStep), uint64(shiftStep.value.x))
  emitArmBranch(body, 171, instructionRegisters(branch), 0, 20, 30)
  ArmRegionBlock(header: 20, span: 5, operations: 5, yes: 20, no: 30,
      price: 5, body: move(body))

proc tailBody(): ArmReadSpan =
  ## Existing cycle read/branch child uses its own descriptor ABI.
  var read = default(ArmReadSpan)
  let first = instruction(tailSource, CodeAddress(0))
  let increment = instruction(tailSource, CodeAddress(6))
  let branch = instruction(tailSource, CodeAddress(9))
  for decoded in [first, increment, branch]: assert decoded.error == ProgramError.None
  emitArmDirectRead(read, instructionRegisters(first), 65544, 57)
  emitArmReadArithmetic(read, 149, instructionRegisters(increment), uint64(increment.value.x))
  emitArmReadBranch(read, 173, instructionRegisters(branch), 0, 10, 40)
  move(read)

proc prefixBody(): ArmBlock =
  ## Three pure increments leave the cycle's R12 untouched.
  result = default(ArmBlock)
  for pc in [0'u64, 3'u64, 6'u64]:
    let decoded = instruction(prefixSource, CodeAddress(pc))
    assert decoded.error == ProgramError.None and decoded.value.opcode == 149
    emitArmOperation(result, 149, instructionRegisters(decoded), uint64(decoded.value.x))

proc publishChildren(jit: ArmJit) =
  ## Publish exact existing dirty and read children before the resident cycle.
  let store = instruction(dirtySource, CodeAddress(3))
  assert store.error == ProgramError.None
  var dirty = dirtyBody()
  assert publishArmDirtyLoop(jit, move(dirty), instructionRegisters(store).bIndex, 0)
  let read = tailBody()
  var words = armReadInstructions(read, 32, true)
  assert publishArmEntry(jit, 31, 32, 3, words)

proc publishCycle(jit: ArmJit) =
  ## Resident child retains the accepted 14-word context and original root record.
  var cycle = ArmMemoryCycleBlock(prefixHeader: 10, dirtyHeader: 20,
      tailHeader: 30, tailEntry: 31, other: 40, prefixSpan: 4, tailSpan: 4,
      prefixOperations: 3, tailOperations: 3, prefixPrice: 7, tailPrice: 11,
      prefixBody: prefixBody(), dirty: dirtyBody(),
      dirtyBaseSlot: instructionRegisters(instruction(dirtySource, CodeAddress(3))).bIndex,
      dirtyDisplacement: 0, tailRead: tailBody())
  assert publishArmResidentMemoryCycle(jit, move(cycle))
  assert armResidentMemoryCycleActive(jit) and armMacroCycleExit(jit) == 40

proc publishPure(jit: ArmJit) =
  ## A one-argument branch body writes guest R12 and selects a real cached arm.
  let increment = instruction(pureSource, CodeAddress(0))
  let branch = instruction(pureSource, CodeAddress(3))
  assert increment.error == ProgramError.None and branch.error == ProgramError.None
  var body = default(ArmBlock)
  emitArmOperation(body, 149, instructionRegisters(increment), uint64(increment.value.x))
  emitArmBranch(body, 81, instructionRegisters(branch), 42, 80, 60)
  var words = armInstructions(body)
  assert publishArmEntry(jit, 51, 52, 2, words)

proc publishRead(jit: ArmJit) =
  ## A two-argument guarded body reads through the fresh descriptor pointer.
  let decoded = instruction(readSource, CodeAddress(0))
  assert decoded.error == ProgramError.None and decoded.value.opcode == 130
  var body = default(ArmReadSpan)
  emitArmRead(body, instructionRegisters(decoded), 8, 130)
  var words = armReadInstructions(body, 72)
  assert publishArmEntry(jit, 71, 72, 1, words)

proc macroShape(): ArmMacroShape =
  ## Stream offsets are synthetic test facts; runtime admission receives source-derived values.
  let branch = instruction(branchSource, CodeAddress(0))
  assert branch.error == ProgramError.None and branch.value.opcode == 88
  ArmMacroShape(cycleHeader: 10, cycleExit: 40, staticHeader: 40,
      staticTarget: 50, pureHeader: 50, pureBody: 51, pureTerminal: 52,
      pureYes: 80, pureNo: 60, branchHeader: 60, branchYes: 50,
      branchNo: 70, readHeader: 70, readBody: 71, readTerminal: 72,
      terminalTarget: 10, staticSpan: 1, pureSpan: 2, branchSpan: 1,
      readSpan: 3, staticPrice: 2, purePrice: 3, branchPrice: 1,
      readPrice: 4, branchSlot: instructionRegisters(branch).aIndex,
      branchImmediate: uint64(branch.value.x))

proc childJit(): ArmJit =
  ## Publish only the three genuine child ABIs in one arena.
  result = newArmJit()
  assert armEntry(result, 0, 128) == 0
  publishChildren(result)
  publishCycle(result)
  publishPure(result)
  publishRead(result)
  let root = armMacroChildRecord(result, 10)
  let pure = armMacroChildRecord(result, 51)
  let read = armMacroChildRecord(result, 71)
  assert root.code >= 2 and pure.code >= 2 and read.code >= 2
  assert pure.operations == 2 and pure.ending == 52 and
      read.operations == 1 and read.ending == 72
  assert armMacroStatus(result) == 0

proc readyJit(): ArmJit =
  ## One additional macro image has its own code record, leaving all child entries intact.
  result = childJit()
  let root = armMacroChildRecord(result, 10)
  let pure = armMacroChildRecord(result, 51)
  let read = armMacroChildRecord(result, 71)
  assert publishArmMacro(result, macroShape())
  assert armMacroStatus(result) == 2 and armMacroMatches(result, macroShape())
  assert armMacroShape(result) == macroShape()
  assert armMacroChildRecord(result, 10) == root and
      armMacroChildRecord(result, 51) == pure and
      armMacroChildRecord(result, 71) == read

type MacroCase = object
  destination: uint32
  registers: RegisterFile
  state: ArmMacroState
  bytes: array[32, byte]

proc runCaseWithHost(jit: ArmJit, gas, attempts, extent, r12: uint64,
    bytes: var array[32, byte], dirtyWords: var seq[uint64]): MacroCase =
  ## Descriptor and bitmap addresses are supplied anew for every invocation.
  var descriptors = default(array[3, array[3, uint64]])
  descriptors[1] = [65536'u64, extent, cast[uint64](addr bytes[0])]
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(65536)
  registers[1] = RegisterValue(0x1234)
  registers[2] = RegisterValue(0xa5)
  registers[3] = RegisterValue(65538)
  registers[7] = RegisterValue(65540)
  registers[12] = RegisterValue(r12)
  var state = default(ArmMacroState)
  state[0] = gas
  state[1] = attempts
  state[13] = uint64(high(uint32))
  state[24] = uint64(high(uint32))
  let destination = callArmMacro(jit, registers, descriptors, dirtyWords, state)
  MacroCase(destination: destination, registers: registers, state: state,
      bytes: bytes)

proc runCase(jit: ArmJit, gas, attempts, extent, r12: uint64): MacroCase =
  var bytes = default(array[32, byte])
  var dirtyWords = newSeq[uint64](16384)
  dirtyWords[0] = 1'u64 shl 16
  runCaseWithHost(jit, gas, attempts, extent, r12, bytes, dirtyWords)

proc checkCase(jit: ArmJit, gas, attempts, extent, r12: uint64,
    destination: uint32, remainingGas, remainingAttempts, last, finalR12,
    nativeOperations: uint64): MacroCase =
  ## Independent literal expectations cover the complete source charge and progress ledger.
  let calls = jit.calls
  let branches = jit.branchCalls
  let headers = jit.headerCalls
  let operations = jit.operations
  let before = armMacroStatistics(jit)
  result = runCase(jit, gas, attempts, extent, r12)
  if result.destination != destination or result.state[0] != remainingGas or
      result.state[1] != remainingAttempts or result.state[24] != last or
      uint64(result.registers[12]) != finalR12:
    echo "ARM_MACRO_MISMATCH,", gas, ",", attempts, ",", extent, ",",
        result.destination, ",", result.state[0], ",", result.state[1], ",",
        result.state[24], ",", uint64(result.registers[12]), ",",
        result.state[14], ",", result.state[15], ",", result.state[16],
        ",", result.state[23], ",", result.state[25]
  assert result.destination == destination and result.state[0] == remainingGas and
      result.state[1] == remainingAttempts and result.state[24] == last and
      uint64(result.registers[12]) == finalR12
  assert jit.calls == calls+1 and jit.branchCalls == branches+1 and
      jit.headerCalls == headers+1 and jit.operations == operations+nativeOperations
  let after = armMacroStatistics(jit)
  assert after[0] == before[0]+1 and after[1] == before[1]+result.state[19]
  assert after[2] == before[2]+result.state[20] and
      after[3] == before[3]+result.state[21] and
      after[4] == before[4]+result.state[22] and
      after[5] == before[5]+result.state[23] and
      after[6] == before[6]+result.state[25]
  assert armMemoryCycleStatistics(jit)[0] == 0 # Nested BLs are not C cycle entries.

proc checkChildAfterRefusal(jit: ArmJit, root, pure, read: ArmMacroChildRecord) =
  ## Failed macro publication cannot change any independently executable child.
  assert armMacroStatus(jit) == 1
  assert armMacroChildRecord(jit, 10) == root and
      armMacroChildRecord(jit, 51) == pure and
      armMacroChildRecord(jit, 71) == read
  var registers = default(RegisterFile)
  registers[12] = RegisterValue(0)
  assert callArmBranch(jit, 51, registers) == 60

proc observedCodeBytes(jit: ArmJit): uint64 {.noinline.} =
  ## Keep the live owner ledger visible across repeated native publication calls.
  jit.codeBytes

when defined(pvmArmMacroPublishRefuse):
  proc checkAppendRefusal(): int =
    ## The private compile switch refuses only the final macro append.
    let denied = childJit()
    let root = armMacroChildRecord(denied, 10)
    let pure = armMacroChildRecord(denied, 51)
    let read = armMacroChildRecord(denied, 71)
    let codeBytes = denied.codeBytes
    let fragments = denied.fragments
    assert not publishArmMacro(denied, macroShape())
    assert denied.codeBytes == codeBytes and denied.fragments == fragments and
        armMacroStatus(denied) == 1 and
        armMacroChildRecord(denied, 10) == root and
        armMacroChildRecord(denied, 51) == pure and
        armMacroChildRecord(denied, 71) == read
    var registers = default(RegisterFile)
    registers[12] = RegisterValue(0)
    assert callArmBranch(denied, 51, registers) == 60
    result = 2

when defined(pvmArm64JitRefuse):
  proc checkNativeRefusal(): int =
    ## Failed executable allocation remains sticky and never publishes a child.
    let denied = newArmJit()
    assert armEntry(denied, 0, 128) == 0
    var words: seq[uint32] = @[0xd503201f'u32]
    assert not publishArmEntry(denied, 10, 11, 1, words)
    assert denied.fragments == 0 and denied.codeBytes == 0
    assert armEntry(denied, 10, 128) == 1
    assert not publishArmMacro(denied, macroShape())
    assert armMacroStatus(denied) == 1
    assert not publishArmMacro(denied, macroShape())
    assert denied.fragments == 0 and denied.codeBytes == 0
    result = 2

proc armMacroBackendControls*(): int =
  ## One receipt is emitted by the caller after all applicable literal controls pass.
  result = checkEmpty()
  when defined(pvmArm64JitRefuse):
    result += checkNativeRefusal()
  elif defined(pvmArmMacroPublishRefuse):
    result += checkAppendRefusal()
  else:
    let jit = readyJit()
    var shapeCopy = armMacroShape(jit)
    shapeCopy.staticPrice += 1
    assert not armMacroMatches(jit, shapeCopy) and armMacroMatches(jit, macroShape())
    const noHeader = uint64(high(uint32))
    let complete = checkCase(jit, 1000, 43, 16, 0, 10, 934, 0, 70, 1, 38)
    assert complete.state[14] == 2 and complete.state[15] == 2 and
        complete.state[16] == 4 and complete.state[17] == 0 and
        complete.state[18] == 2 and complete.state[19] == 2 and
        complete.state[20] == 1 and complete.state[21] == 1 and
        complete.state[22] == 1 and complete.state[23] == 1 and
        complete.state[25] == 0 and complete.bytes[0] == 0x34
    # The second child made no progress; global word24 stayed read.
    assert complete.state[13] == noHeader
    assert armMacroStatistics(jit) == [1'u64, 2, 1, 1, 1, 1, 0]
    assert armMemoryCycleStatistics(jit) == [0'u64, 2, 2, 4, 0, 2]
    assert armDirtyLoopStatistics(jit) == [2'u64, 4, 0]
    inc result, 1

    # The first failed whole-block guard returns its unstarted header. Zero attempts
    # wins before gas; a partial span never precharges the failed block.
    discard checkCase(jit, 0, 0, 16, 0, 10, 0, 0, noHeader, 0, 0)
    discard checkCase(jit, 1000, 3, 16, 0, 10, 1000, 3, noHeader, 0, 0)
    discard checkCase(jit, 1000, 36, 16, 0, 40, 944, 0, 30, 0, 32)
    discard checkCase(jit, 56, 100, 16, 0, 40, 0, 64, 30, 0, 32)
    discard checkCase(jit, 57, 100, 16, 0, 40, 1, 64, 30, 0, 32)
    discard checkCase(jit, 1000, 37, 16, 0, 50, 942, 0, 40, 0, 33)
    discard checkCase(jit, 1000, 38, 16, 0, 50, 942, 1, 40, 0, 33)
    discard checkCase(jit, 58, 100, 16, 0, 50, 0, 63, 40, 0, 33)
    discard checkCase(jit, 1000, 39, 16, 0, 60, 939, 0, 50, 1, 35)
    discard checkCase(jit, 61, 100, 16, 0, 60, 0, 61, 50, 1, 35)
    let beforeRead = checkCase(jit, 1000, 40, 16, 0, 70, 938, 0, 60, 1, 36)
    discard checkCase(jit, 1000, 41, 16, 0, 70, 938, 1, 60, 1, 36)
    discard checkCase(jit, 1000, 42, 16, 0, 70, 938, 2, 60, 1, 36)
    discard checkCase(jit, 62, 100, 16, 0, 70, 0, 60, 60, 1, 36)
    inc result, 14

    # The resident child's own source prices and spans remain exact inside the BL.
    discard checkCase(jit, 6, 100, 16, 0, 10, 6, 100, noHeader, 0, 0)
    discard checkCase(jit, 7, 100, 16, 0, 20, 0, 96, 10, 0, 3)
    discard checkCase(jit, 12, 100, 16, 0, 20, 0, 91, 20, 0, 8)
    discard checkCase(jit, 34, 100, 16, 0, 10, 6, 82, 30, 0, 16)
    discard checkCase(jit, 45, 100, 16, 0, 30, 0, 68, 20, 0, 29)
    inc result, 5

    # The true signed-LE arm loops back through a second charged pure block. The
    # 64-bit sign extremes also prove that R12/X16 survives every child boundary.
    let backedge = checkCase(jit, 1000, 46, 16, 0xfffffffffffffffe'u64,
        10, 930, 0, 70, 0, 41)
    assert backedge.state[20] == 1 and backedge.state[21] == 2 and
        backedge.state[22] == 2 and backedge.state[23] == 1
    discard checkCase(jit, 1000, 40, 16, 0x8000000000000000'u64,
        50, 938, 0, 60, 0x8000000000000001'u64, 36)
    discard checkCase(jit, 1000, 40, 16, 0x7fffffffffffffff'u64,
        50, 938, 0, 60, 0x8000000000000000'u64, 36)
    let rare = checkCase(jit, 1000, 100, 16, 41, 80, 939, 61, 50, 42, 35)
    assert rare.state[20] == 1 and rare.state[21] == 1 and
        rare.state[22] == 0 and rare.state[23] == 0
    inc result, 4

    # Cycle dirty writes and pure R12 mutation precede this refused later read.
    # Its own 4 gas and 3 source attempts are refunded, and word24 remains branch88.
    let refused = checkCase(jit, 1000, 43, 9, 0, 70, 938, 3, 60, 1, 36)
    assert refused.state[14] == 2 and refused.state[16] == 4 and
        refused.state[19] == 1 and refused.state[20] == 1 and
        refused.state[21] == 1 and refused.state[22] == 1 and
        refused.state[23] == 0 and refused.state[25] == 1 and
        refused.bytes[0] == 0x34 and refused.state[13] == 30
    assert refused.registers == beforeRead.registers and refused.bytes == beforeRead.bytes
    inc result, 1

    block:
      ## Two simultaneously live buffers expose any cached descriptor or bitmap pointer.
      var first = default(array[32, byte])
      var second = default(array[32, byte])
      var firstDirty = newSeq[uint64](16384)
      var secondDirty = newSeq[uint64](16384)
      firstDirty[0] = 1'u64 shl 16
      secondDirty[0] = 1'u64 shl 16
      first[0] = 0x11
      second[0] = 0x22
      assert cast[uint64](addr first[0]) != cast[uint64](addr second[0]) and
          cast[uint64](addr firstDirty[0]) != cast[uint64](addr secondDirty[0])
      let firstResult = runCaseWithHost(jit, 1000, 43, 16, 0, first, firstDirty)
      assert firstResult.destination == 10 and first[0] == 0x34 and second[0] == 0x22
      first[0] = 0x77
      let secondResult = runCaseWithHost(jit, 1000, 43, 16, 0, second, secondDirty)
      assert secondResult.destination == 10 and second[0] == 0x34 and first[0] == 0x77
    inc result, 1

    block:
      ## A different owner has none of the required resident child records.
      let foreign = newArmJit()
      discard armEntry(foreign, 0, 128)
      assert not publishArmMacro(foreign, macroShape()) and
          armMacroStatus(foreign) == 1 and foreign.fragments == 0
      let malformed = childJit()
      let root = armMacroChildRecord(malformed, 10)
      let pure = armMacroChildRecord(malformed, 51)
      let read = armMacroChildRecord(malformed, 71)
      let codeBytes = malformed.codeBytes
      let fragments = malformed.fragments
      var shape = macroShape()
      shape.branchImmediate = 0x100000000'u64 # Not a sign-extended 32-bit source literal.
      assert not publishArmMacro(malformed, shape)
      assert malformed.codeBytes == codeBytes and malformed.fragments == fragments
      checkChildAfterRefusal(malformed, root, pure, read)
    inc result, 2

    block:
      ## Fill the real arena's fragment ledger with valid publications.
      let capped = childJit()
      discard armEntry(capped, 0, 1200)
      let root = armMacroChildRecord(capped, 10)
      let pure = armMacroChildRecord(capped, 51)
      let read = armMacroChildRecord(capped, 71)
      var offset = 100'u32
      while capped.fragments < 1024:
        var words: seq[uint32] = @[0xd503201f'u32]
        assert publishArmEntry(capped, offset, offset+1, 1, words, true)
        inc offset
      let codeBytes = capped.codeBytes
      assert not publishArmMacro(capped, macroShape())
      assert capped.fragments == 1024 and capped.codeBytes == codeBytes
      checkChildAfterRefusal(capped, root, pure, read)
    inc result, 1

    block:
      ## Cross the macro image's byte threshold using real, bounded leaf images.
      let baseline = childJit()
      let macroBytes = observedCodeBytes(jit)-observedCodeBytes(baseline)
      assert macroBytes >= 8 and macroBytes < 4092
      discard armEntry(baseline, 0, 400)
      let root = armMacroChildRecord(baseline, 10)
      let pure = armMacroChildRecord(baseline, 51)
      let read = armMacroChildRecord(baseline, 71)
      var offset = 100'u32
      var used = observedCodeBytes(baseline)
      while 1048576'u64-used >= macroBytes:
        let spare = 1048576'u64-used
        let size = min(4092'u64, max(8'u64, spare-macroBytes+4))
        var words = newSeq[uint32](int(size div 4)-1)
        for index in 0..<words.len: words[index] = 0xd503201f'u32
        assert publishArmEntry(baseline, offset, offset+1, 1, words, true)
        used+=size
        inc offset
      let codeBytes = observedCodeBytes(baseline)
      let fragments = baseline.fragments
      assert codeBytes == used
      assert fragments < 1024 and not publishArmMacro(baseline, macroShape())
      assert observedCodeBytes(baseline) == codeBytes and baseline.fragments == fragments
      checkChildAfterRefusal(baseline, root, pure, read)
    inc result, 1
