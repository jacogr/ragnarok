# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Candidate-local ARM rejection must preserve unrelated native coverage and exact immutable caller state.
import std/[assertions, syncio]
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine, step]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/internal/[handler_stream, arm64_jit]

const
  Native = defined(linux) and defined(arm64) and not defined(pvmArm64JitRefuse)
  SmallPc = 4132'u64
  LargeRound = 4106'u64
  InitialGas = 10000000'u64
  # Independent pinned-GP Python pipeline oracle values, not execution inputs or native observations.
  LargePrice = 5528'u64
  OtherPrice = 4'u64
  SmallPrice = 21'u64
  TailPrice = 2'u64
  TrapPrice = 2'u64

proc require(ok: bool, stage: string) =
  ## Stable diagnostics identify an expected historical regression rather than an unrelated failure.
  if not ok: echo "ARM_REGION_REFUSAL_ASSERT,", stage
  assert ok

proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Only framing uses the independent codec; guest operations and target bytes below are literal.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len: bytes.add(encoded.bytes[index])

proc owner(): Program =
  ## A folded4096-marker prefix violates only regional source span, then an independent two-block loop follows.
  var parts: seq[seq[byte]] = @[]
  for index in 0..<4096: parts.add(@[2'u8])
  for index in 0..<4: parts.add(@[149'u8, 0, 1])
  parts.add(@[172'u8, 0x10, 6, 0, 0, 0]) # PC4108 -> PC4114; both edges name the next valid block.
  for index in 0..<4: parts.add(@[149'u8, 0x22, 1])
  parts.add(@[172'u8, 0x10, 0xe2, 0xef, 0xff, 0xff]) # PC4126 -> PC0, displacement-4126.
  parts.add(@[149'u8, 0, 1])
  parts.add(@[172'u8, 0x10, 6, 0, 0, 0]) # PC4135 -> PC4141.
  parts.add(@[149'u8, 0, 1])
  parts.add(@[172'u8, 0x10, 0xf4, 0xff, 0xff, 0xff]) # PC4144 -> PC4132.
  parts.add(@[0'u8])
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    # Operand bytes must never become admitted instruction boundaries.
    starts.add(code.len)
    for value in part: code.add(value)
  require(code.len == 4151, "literal-source-extent")
  var bytes: seq[byte] = @[]
  appendNatural(bytes, 0)
  bytes.add(0)
  appendNatural(bytes, uint64(code.len))
  for value in code: bytes.add(value)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for value in mask: bytes.add(value)
  let decoded = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(uint64(bytes.len)),
      JumpCountLimit(0))
  require(decoded.error == ProgramError.None, "literal-source-admission")
  decoded.value

proc image(): PageImage =
  ## Nonzero immutable RAM makes complete publication/source preservation observable despite arithmetic-only guests.
  result = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)
  for index in 0..<4096: result.bytes[index] = byte(index mod 251)

proc verify(frame: FlatFrame, expected: MachineInfo, remaining: uint64, limited: bool) =
  ## Expected CPU/gas/attempts and all page bytes are literal/oracle facts, not another prepared execute result.
  require(frame.info == expected and frame.remaining == remaining, "independent-full-cpu-gas-attempts")
  require(preparationError(frame) == FlatError.None, "no-resource-policy-change")
  if limited:
    require(frame.reason == StepError.StepLimitExceeded and frame.exit == StepExit.Continued,
      "literal-large-prefix-exit")
  else:
    require(frame.reason == StepError.None and frame.exit == StepExit.Panic, "literal-small-trap-exit")
  require(uint64(frame.faultPage) == 0, "no-invented-fault")
  checkFlatSource(frame)
  let captured = memoryImages(flatMemorySnapshot(frame))
  require(captured.error == MachineError.None, "full-memory-observation")
  let pages = captured.value
  let original = image()
  require(pages.len == 1, "full-page-catalog")
  require(pages[0].index == original.index and pages[0].access == original.access and
    pages[0].bytes == original.bytes, "independent-full-ram-permissions")

proc runSmall(frame: var FlatFrame) =
  ## Six additions and six branches reach the literal trap; retain a posterior across later resets.
  var input = MachineInfo(pc: CodeAddress(SmallPc), gas: MachineGas(InitialGas))
  input.registers[1] = RegisterValue(6)
  var expected = input
  expected.pc = CodeAddress(0)
  expected.gas = MachineGas(InitialGas-3*(SmallPrice+TailPrice)-TrapPrice)
  expected.registers[0] = RegisterValue(6)
  expected.blockCharged = true
  for visit in 0..<3:
    # Repeated calls retain the same owner but reset only invocation-local state at the explicit boundary.
    resetFlatFrame(frame, input)
    runFlat(frame, 1000)
    verify(frame, expected, 987, false)

proc order(smallFirst, largeFirst: bool): bool =
  ## Fresh-small, rejected-then-small and small-then-rejected owners have the same independent endpoints.
  let program = owner()
  let plan = newFlatPlan(program, GasCycleLimit(1000000))
  var frame = newFlatFrame(plan, [image()], MachineInfo(gas: MachineGas(InitialGas)))
  if smallFirst: runSmall(frame)
  let retained = flatMemorySnapshot(frame)
  if largeFirst:
    var input = MachineInfo(gas: MachineGas(InitialGas))
    input.registers[1] = RegisterValue(1000000)
    var expected = input
    expected.gas = MachineGas(InitialGas-20*(LargePrice+OtherPrice))
    expected.registers[0] = RegisterValue(80)
    expected.registers[2] = RegisterValue(80)
    for visit in 0..<2:
      # Forty source rounds exhaust the existing eight complete discovery visits at each rejected header.
      resetFlatFrame(frame, input)
      runFlat(frame, 20*LargeRound)
      verify(frame, expected, 0, true)
    let stable = flatArmStatistics(frame)
    resetFlatFrame(frame, input)
    runFlat(frame, 20*LargeRound)
    verify(frame, expected, 0, true)
    let after = flatArmStatistics(frame)
    require(after[0] == stable[0] and after[3] == stable[3] and after[4] == stable[4],
      "exhausted-candidate-probes-stable")
  let before = flatArmRegionStatistics(frame)[0]
  runSmall(frame)
  let after = flatArmRegionStatistics(frame)
  let prior = memoryImages(retained)
  require(prior.error == MachineError.None, "retained-snapshot-owner")
  let pages = prior.value
  require(pages.len == 1 and pages[0].bytes == image().bytes, "later-work-preserves-retained-snapshot")
  when Native:
    require(flatArmStatistics(frame)[1] > 0, "ordinary-native-positive")
    result = after[0] > before and after[1] > after[0]
  else:
    require(after == default(array[2, uint64]) and flatArmStatistics(frame)[1] == 0,
      "real-unavailable-or-forced-refusal")
    result = true
  when defined(pvmArm64JitRefusalReceipt):
    echo "ARM_REGION_REFUSAL_NATIVE,", int(smallFirst), ",", int(largeFirst), ",", before,
      ",", after[0], ",", after[1], ",", flatArmStatistics(frame)[1]
  echo "ARM_REGION_REFUSAL_CASE,", smallFirst, ",", largeFirst, ",", result

proc smallBlocks(): array[3, ArmRegionBlock] =
  ## Two authentic existing emitter bodies have explicit scalar source/price proof records.
  let program = owner()
  let add = instructionRegisters(instruction(program, CodeAddress(SmallPc)))
  let branch = instructionRegisters(instruction(program, CodeAddress(SmallPc+3)))
  result = default(array[3, ArmRegionBlock])
  for index in 0..<2:
    var body = newArmRegionBody()
    emitArmOperation(body, 149, add, 1)
    let yes = if index == 0: 8'u32 else: 7'u32
    let no = if index == 0: 8'u32 else: 12'u32
    emitArmBranch(body, 172, branch, 0, yes, no)
    result[index] = ArmRegionBlock(header: uint32(7+index), span: 2, operations: 2,
      yes: yes, no: no, price: if index == 0: SmallPrice else: TailPrice, body: move(body))

proc controls(): bool =
  ## Candidate shape/span failures stay local; unsupported storage and genuine global exhaustion stay sticky.
  result = true
  for shape in 0..<4:
    let jit = newArmJit()
    discard armEntry(jit, 0, 16)
    var blocks = smallBlocks()
    case shape
    of 0: blocks[0].span = 1
    of 1: blocks[0].span = 4096
    of 2: blocks[0].body = default(ArmBlock)
    else:
      # A candidate may fit its source-span ceiling yet exceed the unchanged generated-word ceiling.
      let program = owner()
      let add = instructionRegisters(instruction(program, CodeAddress(SmallPc)))
      let branch = instructionRegisters(instruction(program, CodeAddress(SmallPc+3)))
      var body = newArmRegionBody()
      for operation in 0..<1100: emitArmOperation(body, 149, add, 1)
      emitArmBranch(body, 172, branch, 0, 8, 8)
      blocks[0].span = 1101
      blocks[0].operations = 1101
      blocks[0].body = move(body)
    require(not publishArmRegion(jit, blocks, 2), "candidate-local-decline")
    result = result and armRegionStatus(jit) == 0
    require(jit.fragments == 0 and jit.codeBytes == 0, "candidate-no-storage-mutation")
  let probes = newArmJit()
  discard armEntry(probes, 0, 16)
  armStartProbe(probes, 3)
  for visit in 1..8: require(armFinishProbe(probes, 3) == (visit == 8), "exact-eight-probe-bound")
  when Native:
    let counted = newArmJit()
    discard armEntry(counted, 0, 4096)
    for index in 0..<1024:
      # Exercise the existing reserved-slot API explicitly; real publications, not forged counter assignment.
      var words: seq[uint32] = @[0xd503201f'u32]
      require(publishArmEntry(counted, uint32(index), uint32(index+1), 1, words, true),
        "fill-existing-publication-ceiling")
    require(counted.fragments == 1024 and armRegionStatus(counted) == 0, "real-publication-ceiling")
    let before = [counted.fragments, counted.codeBytes]
    require(not publishArmRegion(counted, smallBlocks(), 2) and armRegionStatus(counted) == 1,
      "global-publication-refusal-sticky")
    require([counted.fragments, counted.codeBytes] == before, "global-refusal-no-publication")
    var registers = default(RegisterFile)
    require(callArmEntry(counted, 0, registers) == 1, "global-refusal-retains-ordinary-entry")
    let physical = newArmJit()
    discard armEntry(physical, 0, 4096)
    var coordinate = 0'u32
    var full = false
    while not full and coordinate < 1023:
      # Long real NOP bodies fill physical arena bytes before exhausting the publication-count ceiling.
      var words: seq[uint32] = @[]
      for index in 0..<1022: words.add(0xd503201f'u32)
      if not publishArmEntry(physical, coordinate, coordinate+1, 1022, words): full = true
      inc coordinate
    require(full and physical.fragments > 0 and physical.fragments < 1023, "physical-byte-ceiling")
    full = false
    while not full and coordinate < 4095:
      var words: seq[uint32] = @[0xd503201f'u32]
      if not publishArmEntry(physical, coordinate, coordinate+1, 1, words): full = true
      inc coordinate
    let original = [physical.fragments, physical.codeBytes]
    require(full and original[1] <= 1048576, "physical-exact-capacity")
    require(not publishArmRegion(physical, smallBlocks(), 2) and armRegionStatus(physical) == 1,
      "global-physical-refusal-sticky")
    require([physical.fragments, physical.codeBytes] == original and
      callArmEntry(physical, 0, registers) == 1, "physical-refusal-retains-storage")
  else:
    let unavailable = newArmJit()
    discard armEntry(unavailable, 0, 16)
    require(not publishArmRegion(unavailable, smallBlocks(), 2) and armRegionStatus(unavailable) == 1,
      "unavailable-storage-sticky")
    require(unavailable.fragments == 0 and unavailable.calls == 0 and unavailable.codeBytes == 0,
      "unavailable-no-native-claim")
  echo "ARM_REGION_LOCAL_SHAPES,", result

let local = controls()
let fresh = order(false, false)
require(fresh, "fresh-owner-native-positive")
let rejectedFirst = order(false, true)
let eligibleFirst = order(true, true)
require(local and rejectedFirst and eligibleFirst, "candidate-local-availability")
echo "PASS fresh and both same-owner orders / independent CPU RAM gas attempts / immutable snapshots / bounded probes"
