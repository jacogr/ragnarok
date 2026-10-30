# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Isolated x86 owner-state profile: local rejection preserves later regions and strict probe/storage bounds.
import std/[assertions, syncio]
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/step
import ../../../src/pvm/internal/[handler_stream, x86_jit]

const Native = defined(linux) and defined(amd64) and not defined(pvmX86JitRefuse)

proc require(ok: bool, stage: string) =
  ## Stable failure stages distinguish the intended historical negative from any unrelated assertion.
  if not ok: echo "REGION_REFUSAL_ASSERT,", stage
  assert ok

proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Only framing uses the independent codec; instruction, register and branch bytes remain literal.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len: bytes.add(encoded.bytes[index])

proc owner(parts: openArray[seq[byte]]): Program =
  ## Immutable source admission retains explicit original boundaries and never marks operand bytes.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    starts.add(code.len)
    for value in part: code.add(value)
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

let operands = owner([@[215'u8, 0, 2], @[172'u8, 0x10, 0], @[149'u8, 0, 1], @[0'u8]])
let multiplySlots = instructionRegisters(instruction(operands, CodeAddress(0)))
let branchSlots = instructionRegisters(instruction(operands, CodeAddress(3)))
let addSlots = instructionRegisters(instruction(operands, CodeAddress(6)))

proc leaf(slots: RegisterSlots, count: int, multiply: bool): X86Block =
  ## Build only existing independent emitter operations; no bytes or owner internals are patched by the test.
  result = default(X86Block)
  for index in 0..<count: emitX86Operation(result, if multiply: 215'u8 else: 100'u8, slots, 0)

proc small(add, branch: RegisterSlots): array[2, X86RegionBlock] =
  ## One two-operation source block increments R0 until the full-width comparison exits to coordinate12.
  var body = default(X86Block)
  emitX86Operation(body, 149, add, 1)
  emitX86Branch(body, 172, branch, 0, 7, 12)
  result = default(array[2, X86RegionBlock])
  result[0] = X86RegionBlock(header: 7, span: 2, operations: 2, yes: 7, no: 12,
    price: 2, body: move(body))

proc large(multiply, branch: RegisterSlots): array[2, X86RegionBlock] =
  ## Each64-op leaf fits4096bytes; combined guards/body/edges exceed the unchanged connected-code ceiling.
  result = default(array[2, X86RegionBlock])
  for index in 0..<2:
    var body = leaf(multiply, 64, true)
    emitX86Branch(body, 172, branch, 0, uint32(8-index), 12)
    result[index] = X86RegionBlock(header: uint32(7+index), span: 65, operations: 65,
      yes: uint32(8-index), no: 12, price: 65, body: move(body))

proc seed(jit: X86Jit, slots: RegisterSlots) =
  ## Genuine ordinary native publication proves executable storage is working before local rejection.
  require(x86Entry(jit, 0, 256) == 0, "empty-entry")
  require(publishX86Entry(jit, 0, 4, 4, leaf(slots, 4, false)), "ordinary-storage-positive")

block localNegatives:
  # Local shape checks must not poison the sole region, even before any executable allocation exists.
  let jit = newX86Jit()
  var invalid = small(addSlots, branchSlots)
  invalid[0].span = 1
  require(not publishX86Region(jit, invalid, 1), "local-shape-refusal")
  require(x86RegionStatus(jit) == 0, "local-shape-global-status")
  invalid = small(addSlots, branchSlots)
  invalid[0].header = 262144
  require(not publishX86Region(jit, invalid, 1) and x86RegionStatus(jit) == 0, "local-coordinate")
  invalid = small(addSlots, branchSlots)
  invalid[0].operations = 1
  require(not publishX86Region(jit, invalid, 1) and x86RegionStatus(jit) == 0, "local-operation-count")
  invalid = small(addSlots, branchSlots)
  invalid[0].body = leaf(multiplySlots, 4, false)
  require(not publishX86Region(jit, invalid, 1) and x86RegionStatus(jit) == 0, "local-branch-tail")
  require(not publishX86Region(jit, large(multiplySlots, branchSlots), 2), "local-size-refusal")
  require(x86RegionStatus(jit) == 0 and jit.fragments == 0 and jit.codeBytes == 0,
    "local-size-global-status")
  # A valid candidate with no ordinary arena has a genuine lifetime storage refusal, not a local negative.
  require(not publishX86Region(jit, small(addSlots, branchSlots), 1) and x86RegionStatus(jit) == 1,
    "missing-arena-sticky")
echo "PASS candidate-local shape and size / unchanged source and publication bounds"

block boundedProbes:
  # Existing source-coordinate metadata provides exactly eight complete discovery visits without adding a cache.
  let jit = newX86Jit()
  discard x86Entry(jit, 0, 16)
  x86StartProbe(jit, 3)
  for visit in 1..8: require(x86FinishProbe(jit, 3) == (visit == 8), "eight-probe-bound")
  for visit in 0..<64: require(x86FinishProbe(jit, 3), "exhaustion-does-not-wrap")
echo "PASS exact eight-visit negative budget / stable exhaustion"

block sameOwner:
  when Native:
    # A real arena survives multiple local failures, and that same owner must publish and execute a later small region.
    let jit = newX86Jit()
    seed(jit, multiplySlots)
    let before = [jit.fragments, jit.codeBytes]
    require(not publishX86Region(jit, large(multiplySlots, branchSlots), 2), "same-owner-size-refusal")
    require(x86RegionStatus(jit) == 0 and [jit.fragments, jit.codeBytes] == before,
      "same-owner-refusal-preserves-storage")
    var registers = default(RegisterFile)
    require(callX86Entry(jit, 0, registers) == 4, "ordinary-entry-survives")
    require(publishX86Region(jit, small(addSlots, branchSlots), 1), "same-owner-eligible-publication")
    registers[1] = RegisterValue(3)
    var state = [100'u64, 100'u64, 0'u64, 0'u64, uint64(high(uint32))]
    require(callX86Region(jit, registers, state) == 12, "same-owner-native-exit")
    require(uint64(registers[0]) == 3 and state == [94'u64, 94'u64, 3'u64, 0'u64, 7'u64],
      "same-owner-native-literal-state")
  else:
    # Explicit OS refusal and unsupported hosts retain canonical fallback, with no fake positive-native claim.
    let jit = newX86Jit()
    discard x86Entry(jit, 0, 16)
    require(not publishX86Entry(jit, 0, 4, 4, leaf(multiplySlots, 4, false)), "arena-refusal")
    require(not publishX86Region(jit, small(addSlots, branchSlots), 1) and x86RegionStatus(jit) == 1,
      "arena-refusal-sticky")
    require(jit.fragments == 0 and jit.calls == 0 and jit.codeBytes == 0, "refusal-no-native-work")
echo "PASS same-owner rejected then eligible / ordinary native preservation / real refusal fallback"

block globalExhaustion:
  when Native:
    # Consume the genuine1024-publication ceiling without increasing the physical arena or forging counters.
    let counted = newX86Jit()
    discard x86Entry(counted, 0, 65536)
    for index in 0..<1024:
      let offset = uint32(index*4)
      require(publishX86Entry(counted, offset, offset+4, 4, leaf(multiplySlots, 4, false)),
        "fill-publication-capacity")
    require(counted.fragments == 1024 and x86RegionStatus(counted) == 0, "exact-publication-capacity")
    require(not publishX86Region(counted, small(addSlots, branchSlots), 1) and
      x86RegionStatus(counted) == 1, "publication-capacity-sticky")
    var registers = default(RegisterFile)
    require(callX86Entry(counted, 0, registers) == 4, "capacity-preserves-first-leaf")
    # Fill actual byte capacity first with long leaves, then shorter leaves, staying below1024 publications.
    let physical = newX86Jit()
    discard x86Entry(physical, 0, 65536)
    var coordinate = 0'u32
    var full = false
    while not full and coordinate < 64000:
      if not publishX86Entry(physical, coordinate, coordinate+64, 64, leaf(multiplySlots, 64, true)):
        full = true
      coordinate+=64
    require(full and physical.fragments > 0 and physical.fragments < 1024, "long-leaf-byte-refusal")
    full = false
    while not full and coordinate < 65000:
      if not publishX86Entry(physical, coordinate, coordinate+4, 4, leaf(multiplySlots, 4, false)):
        full = true
      coordinate+=4
    require(full and physical.fragments < 1024 and physical.codeBytes <= 1048576,
      "exact-physical-capacity")
    let before = [physical.fragments, physical.codeBytes]
    require(not publishX86Region(physical, small(addSlots, branchSlots), 1) and
      x86RegionStatus(physical) == 1, "physical-publication-sticky")
    require([physical.fragments, physical.codeBytes] == before, "failed-physical-publication-atomic")
    require(callX86Entry(physical, 0, registers) == 64, "physical-refusal-preserves-first-leaf")
echo "PASS genuine publication and physical capacity / sticky global refusal / retained native leaves"

proc source(): Program =
  ## Two long blocks close an oversized pair; a later separate small loop fits the same immutable source owner.
  var parts: seq[seq[byte]] = @[]
  for blockIndex in 0..<2:
    for operation in 0..<64: parts.add(@[215'u8, 0, 2])
    if blockIndex == 0:
      # PC192 targets PC198 with signed displacement6.
      parts.add(@[172'u8, 0x10, 6, 0, 0, 0])
    else:
      # PC390 targets PC0 with signed little-endian displacement-390.
      parts.add(@[172'u8, 0x10, 0x7a, 0xfe, 0xff, 0xff])
  parts.add(@[149'u8, 0, 1])
  # PC399 targets PC396; its untaken arm reaches the original trap at405.
  parts.add(@[172'u8, 0x10, 0xfd, 0xff, 0xff, 0xff])
  parts.add(@[0'u8])
  owner(parts)

proc verify(frame: FlatFrame, checked: FlatFrame) =
  ## Complete CPU includes gas, deficit, paid state and every register; attempts and immutable source are separate.
  require(frame.reason == checked.reason and frame.exit == checked.exit, "source-complete-exit")
  require(frame.info == checked.info and frame.remaining == checked.remaining, "source-complete-cpu-attempts")
  require(preparationError(frame) == FlatError.None, "source-preparation-success")
  checkFlatSource(frame, [])

proc sourceOrder(smallFirst: bool) =
  ## Both guest orders preserve native coverage and exact outcomes, and repeated invalid pairs exhaust their probe work.
  let program = source()
  let plan = newFlatPlan(program, GasCycleLimit(1000000))
  var prepared = prepareFlatPlan(program, GasCycleLimit(1000000), defaultFlatLimits(), false)
  require(prepared.error == FlatError.None, "checked-plan")
  let checkedPlan = takeValue(prepared)
  var info = MachineInfo(gas: MachineGas(100000))
  info.registers[1] = RegisterValue(5)
  var frame = newFlatFrame(plan, [], info)
  var checked = newFlatFrame(checkedPlan, [], info)
  if smallFirst:
    # Publishing an eligible region first must retain the existing single-region selection policy.
    info.pc = CodeAddress(396)
    for visit in 0..<3:
      resetFlatFrame(frame, info)
      resetFlatFrame(checked, info)
      runFlat(frame, 1000)
      runFlat(checked, 1000)
      verify(frame, checked)
  info.pc = CodeAddress(0)
  for visit in 0..<2:
    #100 complete long-block visits exceed both existing eight-probe budgets without relaxing source attempts.
    resetFlatFrame(frame, info)
    resetFlatFrame(checked, info)
    runFlat(frame, 6500)
    runFlat(checked, 6500)
    verify(frame, checked)
    require(frame.reason == StepError.StepLimitExceeded and uint64(frame.info.pc) == 0,
      "large-pair-literal-prefix")
  let stable = flatX86Statistics(frame)
  resetFlatFrame(frame, info)
  runFlat(frame, 6500)
  let after = flatX86Statistics(frame)
  require(after[0] == stable[0] and after[3] == stable[3] and after[4] == stable[4],
    "exhausted-negative-does-not-recompile")
  info.pc = CodeAddress(396)
  let before = flatX86RegionStatistics(frame)[0]
  for visit in 0..<3:
    # A prior local rejection cannot consume this unrelated eligible header's independent discovery budget.
    resetFlatFrame(frame, info)
    resetFlatFrame(checked, info)
    runFlat(frame, 1000)
    runFlat(checked, 1000)
    verify(frame, checked)
    require(frame.exit == StepExit.Panic and uint64(frame.info.pc) == 0 and
      uint64(frame.info.registers[0]) == 5 and frame.remaining == 989, "small-loop-literal-endpoint")
  when Native:
    require(flatX86RegionStatistics(frame)[0] > before, "later-eligible-native-region")
    require(flatX86Statistics(frame)[1] > 0, "ordinary-native-still-working")
  else:
    require(flatX86RegionStatistics(frame) == default(array[2, uint64]) and
      flatX86Statistics(frame)[1] == 0, "checked-refusal-counters")
  for pc in [0'u64, 198, 396, 405]:
    for paid in [false, true]:
      for gas in [0'u64, 1, 2, 64, 65, 130, 100000]:
        for budget in [0'u64, 1, 2, 3, 64, 65, 66, 129, 130, 131]:
          # Zero, short and exact budgets cover every original header, an existing region and a literal trap.
          info.pc = CodeAddress(pc)
          info.gas = MachineGas(gas)
          info.blockCharged = paid
          resetFlatFrame(frame, info)
          resetFlatFrame(checked, info)
          runFlat(frame, budget)
          runFlat(checked, budget)
          verify(frame, checked)

sourceOrder(false)
sourceOrder(true)
echo "PASS both guest orders / later eligible native coverage / exhausted retries / full CPU and attempts"
