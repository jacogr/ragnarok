# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Typed local preparation limits, exact cache admission and repairable host refusals.
import std/[assertions, syncio]
import ../../../src/pvm/internal/handler_stream
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/step
proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Test framing uses the independent natural codec without borrowing program storage.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len:
    # Only the explicitly encoded prefix belongs to the output.
    bytes.add(encoded.bytes[index])

proc owner(parts: openArray[seq[byte]], jumps: openArray[uint32] = []): Program =
  ## Explicit instruction boundaries support long blocks and saturated operands without a production assembler.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    # Caller-provided operand bytes never become instruction boundaries.
    starts.add(code.len)
    for value in part: code.add(value)
  var bytes: seq[byte] = @[]
  appendNatural(bytes, uint64(jumps.len))
  bytes.add(if jumps.len == 0: 0'u8 else: 4'u8)
  appendNatural(bytes, uint64(code.len))
  for target in jumps:
    # Fixed four-byte table entries are independent of operand decoding and may deliberately name invalid code targets.
    for shift in 0..<4: bytes.add(byte((uint64(target) shr (shift*8)) and 255))
  for value in code: bytes.add(value)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts:
    # Mark the original opcode positions only.
    mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for value in mask: bytes.add(value)
  let decoded = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(65536),
      JumpCountLimit(1024))
  assert decoded.error == ProgramError.None
  decoded.value

proc sameCpu(left, right: MachineInfo) =
  ## All copied CPU fields participate, including the prepaid-block state and reserved gas deficit.
  assert uint64(left.pc) == uint64(right.pc)
  assert uint64(left.gas) == uint64(right.gas)
  assert uint64(left.gasDeficit) == uint64(right.gasDeficit)
  assert left.blockCharged == right.blockCharged
  for index in 0..<13:
    # Compare every register, including operands intentionally aliased by a witness.
    assert uint64(left.registers[index]) == uint64(right.registers[index])


# A genuine Program already requires a terminating final instruction, so folded noops always have a physical successor.
let noTerminator = decodeProgram(@[0'u8, 0, 1, 2, 1], CodeAddress(0),
  ProgramByteLimit(65536), JumpCountLimit(1024))
assert noTerminator.error == ProgramError.InvalidProgram

let cycles = GasCycleLimit(100000)
let small = owner([@[2'u8], @[50'u8, 0]])
var limits = defaultFlatLimits()
let uninitialized = default(FlatResult[uint64])
assert uninitialized.error == FlatError.Uninitialized
let invalidProgram = default(Program)
assert prepareFlatPlan(invalidProgram, cycles, limits).error == FlatError.InvalidProgram
limits.codeBytes = ProgramByteLimit(2)
assert prepareFlatPlan(small, cycles, limits).error == FlatError.CodeLimitExceeded
limits = defaultFlatLimits()
limits.facts = FlatFactLimit(1)
assert prepareFlatPlan(small, cycles, limits).error == FlatError.FactLimitExceeded
limits = defaultFlatLimits()
limits.jumps = JumpCountLimit(0)
assert prepareFlatPlan(owner([@[50'u8, 0]], [0'u32]), cycles, limits).error ==
    FlatError.JumpLimitExceeded
limits = defaultFlatLimits()
limits.nodes = FlatNodeLimit(2147483647)
assert prepareFlatPlan(small, cycles, limits).error == FlatError.InvalidPolicy

echo "PASS plan admission reasons / code-facts-jumps-policy / result consumption"

# Different interior entries used to append overlapping suffixes without a total stream ceiling.
var parts: seq[seq[byte]] = @[]
for i in 0..<16: parts.add(@[2'u8])
parts.add(@[50'u8, 0])
let source = owner(parts)
limits = defaultFlatLimits()
limits.nodes = FlatNodeLimit(6)
limits.pages = PageLimit(0)
var admitted = prepareFlatPlan(source, cycles, limits)
assert admitted.error == FlatError.None
let plan = takeValue(admitted)
assert admitted.error == FlatError.Uninitialized
limits.nodes = FlatNodeLimit(0) # Admission captured a value; caller mutation cannot change its policy.
var regs = default(RegisterFile)
regs[0] = RegisterValue(0xffff0000'u64)
var info = MachineInfo(gas: MachineGas(1000), registers: regs)
let empty = captureMemory([], PageLimit(0)).value
var constructed = prepareFlatFrame(plan, [], info)
assert constructed.error == FlatError.None
var frame = takeValue(constructed)
assert constructed.error == FlatError.Uninitialized
for pc in 0'u64..2'u64:
  # Folded noops contribute source attempts, but each complete suffix emits exactly one header and halt node.
  info.pc = CodeAddress(pc)
  resetFlatFrame(frame, info)
  runFlat(frame, 64)
  let expected = execute(captureMachine(source, empty, info).value, ExecutionStepLimit(64), cycles)
  assert expected.error == StepError.None and frame.reason == StepError.None
  assert frame.exit == expected.value.exit
  sameCpu(frame.info, machineInfo(expected.value.machine).value)
  assert flatNodes(frame) == 2*int(pc+1)
  assert preparationError(frame) == FlatError.None
  let occupied = flatNodes(frame)
  resetFlatFrame(frame, info)
  runFlat(frame, 64)
  # A cached admitted suffix remains usable at an exactly full cache without another allocation.
  assert frame.reason == StepError.None and flatNodes(frame) == occupied
info.pc = CodeAddress(3)
resetFlatFrame(frame, info)
runFlat(frame, 64)
assert frame.reason == StepError.InvalidPreparedProgram
assert preparationError(frame) == FlatError.StreamLimitExceeded
assert frame.exit == StepExit.Continued and flatNodes(frame) == 6
sameCpu(frame.info, info)
resetFlatFrame(frame, info)
runFlat(frame, 64)
assert frame.reason == StepError.InvalidPreparedProgram and flatNodes(frame) == 6

echo "PASS exact six-node suffix ceiling / folded noops / sticky local refusal"

# Small folded streams can still repeat large pricing/emission spans; their independent preparation allowance must also stop growth.
limits = defaultFlatLimits()
limits.nodes = FlatNodeLimit(6)
limits.pages = PageLimit(0)
limits.preparation = FlatPreparationLimit(34)
var workPlanResult = prepareFlatPlan(source, cycles, limits)
let workPlan = takeValue(workPlanResult)
info.pc = CodeAddress(0)
var workFrame = newFlatFrame(workPlan, [], info)
runFlat(workFrame, 64)
assert workFrame.reason == StepError.None and flatNodes(workFrame) == 2
assert flatPreparationUnits(workFrame) == 34
resetFlatFrame(workFrame, info)
runFlat(workFrame, 64)
assert workFrame.reason == StepError.None and flatPreparationUnits(workFrame) == 34
assert replaceFlatMemoryChecked(workFrame, [], info) == FlatError.None
assert flatPreparationUnits(workFrame) == 34
info.pc = CodeAddress(1)
resetFlatFrame(workFrame, info)
runFlat(workFrame, 64)
assert workFrame.reason == StepError.InvalidPreparedProgram
assert preparationError(workFrame) == FlatError.PreparationLimitExceeded
assert flatNodes(workFrame) == 2 and flatPreparationUnits(workFrame) == 34
sameCpu(workFrame.info, info)
assert replaceFlatMemoryChecked(workFrame, [], info) == FlatError.None
runFlat(workFrame, 64)
assert preparationError(workFrame) == FlatError.PreparationLimitExceeded
assert flatPreparationUnits(workFrame) == 34 and flatNodes(workFrame) == 2
limits.preparation = FlatPreparationLimit(33)
var shortWorkResult = prepareFlatPlan(source, cycles, limits)
let shortWorkPlan = takeValue(shortWorkResult)
info.pc = CodeAddress(0)
var shortWorkFrame = newFlatFrame(shortWorkPlan, [], info)
runFlat(shortWorkFrame, 64)
assert preparationError(shortWorkFrame) == FlatError.PreparationLimitExceeded
assert flatNodes(shortWorkFrame) == 0 and flatPreparationUnits(shortWorkFrame) == 0
echo "PASS independent preparation span ceiling / full-cache reuse / reset and replacement preservation"

# Zero attempts still win without preparing code; an actual request with a zero node budget refuses locally.
limits = defaultFlatLimits()
limits.nodes = FlatNodeLimit(0)
info.pc = CodeAddress(0)
var zeroPlanResult = prepareFlatPlan(small, cycles, limits)
let zeroPlan = takeValue(zeroPlanResult)
var zero = newFlatFrame(zeroPlan, [], info)
runFlat(zero, 0)
assert zero.reason == StepError.StepLimitExceeded and preparationError(zero) == FlatError.None
runFlat(zero, 1)
assert zero.reason == StepError.InvalidPreparedProgram and preparationError(zero) ==
    FlatError.StreamLimitExceeded
assert flatNodes(zero) == 0

echo "PASS zero attempts precede zero-node admission"

# A genuine jump whose destination cannot be admitted must not turn policy exhaustion into guest panic.
let jumping = owner([@[40'u8, 2], @[50'u8, 0]])
limits = defaultFlatLimits()
limits.nodes = FlatNodeLimit(2)
var jumpResult = prepareFlatPlan(jumping, cycles, limits)
let jumpPlan = takeValue(jumpResult)
info.pc = CodeAddress(0)
var jumpFrame = newFlatFrame(jumpPlan, [], info)
runFlat(jumpFrame, 64)
assert jumpFrame.reason == StepError.InvalidPreparedProgram
assert preparationError(jumpFrame) == FlatError.StreamLimitExceeded
assert jumpFrame.exit == StepExit.Continued and flatNodes(jumpFrame) == 2

echo "PASS jump preparation refusal stays separate from guest panic"

# Complete page validation precedes owned copies; checked replacement leaves refused state usable.
limits = defaultFlatLimits()
limits.pages = PageLimit(1)
var pagePlanResult = prepareFlatPlan(small, cycles, limits)
let pagePlan = takeValue(pagePlanResult)
var images = [PageImage(index: PageIndex(16), access: PageAccess.ReadWrite),
  PageImage(index: PageIndex(17), access: PageAccess.ReadWrite)]
images[0].bytes[0] = 77
assert prepareFlatFrame(pagePlan, images, info).error == FlatError.PageLimitExceeded
var invalid = images[0]
invalid.index = PageIndex(1048576)
assert prepareFlatFrame(pagePlan, [invalid], info).error == FlatError.InvalidMemory
var pageFrameResult = prepareFlatFrame(pagePlan, [images[0]], info)
assert pageFrameResult.error == FlatError.None
var pageFrame = takeValue(pageFrameResult)
assert replaceFlatMemoryChecked(pageFrame, images, info) == FlatError.PageLimitExceeded
sameCpu(pageFrame.info, info)
assert pageImage(flatMemorySnapshot(pageFrame), PageIndex(16)).value.bytes[0] == 77
assert replaceFlatMemoryChecked(pageFrame, [images[0]], info) == FlatError.None

echo "PASS page admission and refused replacement preserve complete frame"

# Oversized host mappings refuse before copied deltas and preserve the same suspension for a valid retry.
let hosting = owner([@[10'u8, 1], @[50'u8, 0]])
var hostPlanResult = prepareFlatPlan(hosting, cycles, limits)
let hostPlan = takeValue(hostPlanResult)
var hostFrame = newFlatFrame(hostPlan, [images[0]], info)
runFlat(hostFrame, 64)
assert hostFrame.reason == StepError.None and hostFrame.exit == StepExit.Host
let suspended = hostFrame.info
let hostWork = flatPreparationUnits(hostFrame)
let hostNodes = flatNodes(hostFrame)
assert hostWork == 4 and hostNodes == 3
let observation = observeFlatHostMemory(hostFrame)
let oversized = captureMemory(images, PageLimit(2)).value
assert resumeFlatHostMemory(hostFrame, oversized, suspended.gas, suspended.registers) ==
    StepError.InvalidHostResponse
sameCpu(hostFrame.info, suspended)
assert hostFrame.exit == StepExit.Host and preparationError(hostFrame) == FlatError.None
assert flatPreparationUnits(hostFrame) == hostWork
assert resumeFlatHostMemory(hostFrame, observation, suspended.gas, suspended.registers) == StepError.None
runFlat(hostFrame, 64)
assert hostFrame.reason == StepError.None and hostFrame.exit == StepExit.Halt
if flatPreparationUnits(hostFrame) != hostWork or flatNodes(hostFrame) != hostNodes:
  # A paid continuation now reuses this admitted body; retain precise evidence if suffix growth returns.
  echo "HOST_RESOURCE_FAST_GROWTH,", flatPreparationUnits(hostFrame), ",", flatNodes(hostFrame)
assert flatPreparationUnits(hostFrame) == hostWork and flatNodes(hostFrame) == hostNodes
# A mapping replacement takes the real fallback path and must retain the same preparation reservations and code links.
resetFlatFrame(hostFrame, info)
runFlat(hostFrame, 64)
assert hostFrame.reason == StepError.None and hostFrame.exit == StepExit.Host
let replacementObservation = observeFlatHostMemory(hostFrame)
let replacedMapping = captureMemory([images[1]], PageLimit(1)).value
let beforeReplacement = flatPreparationUnits(hostFrame)
let replacementCpu = hostFrame.info
assert resumeFlatHostMemory(hostFrame, replacedMapping, replacementCpu.gas,
  replacementCpu.registers) == StepError.None
assert flatPreparationUnits(hostFrame) == beforeReplacement
runFlat(hostFrame, 64)
assert hostFrame.reason == StepError.None and hostFrame.exit == StepExit.Halt
if flatPreparationUnits(hostFrame) != hostWork or flatNodes(hostFrame) != hostNodes:
  # Slow mapping replacement must preserve the same code-only occupancy as the fast host resume.
  echo "HOST_RESOURCE_MAPPING_GROWTH,", flatPreparationUnits(hostFrame), ",", flatNodes(hostFrame)
assert flatPreparationUnits(hostFrame) == hostWork and flatNodes(hostFrame) == hostNodes
assert flatHostStats(hostFrame)[1] == 1
assert pageImage(replacementObservation, PageIndex(16)).value.bytes[0] == 77
assert pageImage(flatMemorySnapshot(hostFrame), PageIndex(17)).value.bytes == images[1].bytes
checkFlatSource(hostFrame, [images[1]])
let invalidMemory = default(Memory)
assert memoryPageCount(invalidMemory).error == MachineError.InvalidOwner
assert uint32(memoryPageCount(observation).value) == 1

proc posteriorOwnerReentry() =
  ## Changed writable deltas and full readonly/inaccessible replacements retain exact posterior owners.
  let program = owner([@[10'u8, 1], @[10'u8, 1], @[130'u8, 0x18, 0],
    @[149'u8, 0x88, 1], @[149'u8, 0x88, 1], @[149'u8, 0x88, 1], @[149'u8, 0x88, 1],
    @[50'u8, 0]])
  var policy = defaultFlatLimits()
  policy.pages = PageLimit(4)
  var admitted = prepareFlatPlan(program, cycles, policy)
  let plan = takeValue(admitted)
  var original = [PageImage(index: PageIndex(16), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(17), access: PageAccess.ReadOnly),
    PageImage(index: PageIndex(18), access: PageAccess.Inaccessible)]
  for page in 0..<original.len:
    # Every retained inaccessible byte participates in the independent snapshot witness.
    for offset in 0..<4096: original[page].bytes[offset] = byte((offset+page*17) mod 251)
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000'u64)
  registers[1] = RegisterValue(69632)
  var current = newFlatFrame(plan, original, MachineInfo(gas: MachineGas(10000),
    registers: registers))
  runFlat(current, 3)
  assert current.reason == StepError.None and current.exit == StepExit.Host
  let held = observeFlatHostMemory(current)
  var writable = original[0]
  writable.bytes[9] = 88
  let changed = withReplacedPages(held, [writable]).value
  registers[7] = RegisterValue(77)
  assert resumeFlatHostMemory(current, changed, MachineGas(950), registers) == StepError.None
  assert current.info.pc == CodeAddress(2) and current.info.blockCharged
  assert flatHostStats(current) == [1'u64, 0, 1]
  assert samePage(flatMemorySnapshot(current), changed, PageIndex(16))
  runFlat(current, 2)
  assert current.reason == StepError.None and current.exit == StepExit.Host
  let before = observeFlatHostMemory(current)
  let stopped = current.info
  let nodes = flatNodes(current)
  let work = flatPreparationUnits(current)
  var expected = original
  expected[0] = writable
  # Fresh readonly bytes distinguish the replacement native view from the old allocation.
  for offset in 0..<8: expected[1].bytes[offset] = 0
  expected[1].bytes[0] = 77
  expected[1].bytes[23] = 99
  expected[2].bytes[4095] = 111
  let posterior = captureMemory(expected, PageLimit(3)).value
  let oversized = captureMemory([expected[0], expected[1], expected[2],
    PageImage(index: PageIndex(19)), PageImage(index: PageIndex(20))], PageLimit(5)).value
  registers[8] = RegisterValue(123)
  assert resumeFlatHostMemory(current, oversized, MachineGas(900), registers) ==
    StepError.InvalidHostResponse
  sameCpu(current.info, stopped)
  assert current.exit == StepExit.Host and flatHostStats(current) == [1'u64, 0, 1]
  assert flatNodes(current) == nodes and flatPreparationUnits(current) == work
  for page in expected:
    # Failed admission cannot consume the stopped observation or apply an earlier writable delta.
    assert samePage(flatMemorySnapshot(current), before, page.index)
  assert resumeFlatHostMemory(current, posterior, MachineGas(900), registers) == StepError.None
  assert current.info.pc == CodeAddress(4) and current.info.blockCharged
  assert current.info.registers == registers and uint64(current.info.gas) == 900
  assert flatHostStats(current) == [1'u64, 1, 1]
  assert flatNodes(current) == nodes and flatPreparationUnits(current) == work
  let resumed = flatMemorySnapshot(current)
  for page in 0..<expected.len:
    # Equal-byte writable replacement still has its fresh identity; all posterior pages stay authoritative.
    assert samePage(resumed, posterior, expected[page].index)
    assert not samePage(resumed, before, expected[page].index)
    assert pageImage(resumed, expected[page].index).value == expected[page]
    assert pageImage(held, original[page].index).value == original[page]
  assert withPage(resumed, PageImage(index: PageIndex(19))).error == MachineError.LimitExceeded
  when defined(pvmArm64Jit) and defined(arm64) and not defined(pvmArm64JitRefuse):
    # The read uses the accepted posterior through checked handlers; shared native memory is unported.
    let native = flatArmStatistics(current)
    assert native == default(array[5, uint64]), "unbound posterior-owner read has no native image"
  runFlat(current, 6)
  registers[8] = RegisterValue(81)
  assert current.reason == StepError.None and current.exit == StepExit.Halt
  assert uint64(current.info.gas) == 900 and current.info.registers == registers
  when defined(pvmArm64Jit) and defined(arm64) and not defined(pvmArm64JitRefuse):
    let executed = flatArmStatistics(current)
    # Full literal read/CPU/gas and retained-owner checks above prove semantics, with no native substitute.
    assert executed == native, "posterior-owner checked read does not publish or enter native code"

proc extraLifecyclePages(memory: Memory, expected: openArray[PageImage]) =
  ## Every mapped byte/access tag, including untouched RO and inaccessible payloads, remains observable.
  let count = memoryPageCount(memory)
  assert count.error == MachineError.None and uint32(count.value) == uint32(expected.len)
  for image in expected:
    let actual = pageImage(memory, image.index)
    assert actual.error == MachineError.None and actual.value == image
  # An absent in-domain page has a copied inaccessible image but still faults on canonical guest loads.
  let hole = pageImage(memory, PageIndex(34))
  assert hole.error == MachineError.None
  assert hole.value == PageImage(index: PageIndex(34), access: PageAccess.Inaccessible,
    bytes: default(array[4096, byte]))
  let fault = load(memory, MemoryAddress(34'u64*4096), AccessWidth(1))
  assert fault.error == MachineError.Fault and uint32(fault.faultPage) == 34'u32*4096

proc extraOwnerLifecycle() =
  ## Host rebasing, first cross-page store, scalar continuation and scratch restore share complete byte oracles.
  let program = owner([@[10'u8, 1], @[58'u8, 7, 0, 0, 2, 0], @[52'u8, 11, 6, 0, 3, 0],
    @[33'u8, 4, 255, 15, 2, 0, 120, 86, 52, 18], @[10'u8, 1], @[10'u8, 1],
    @[58'u8, 8, 255, 15, 2, 0], @[52'u8, 9, 6, 0, 3, 0],
    @[52'u8, 10, 19, 16, 2, 0], @[10'u8, 1], @[0'u8]])
  let plan = newFlatPlan(program, cycles)
  var original = [PageImage(index: PageIndex(16), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(17), access: PageAccess.ReadOnly),
    PageImage(index: PageIndex(32), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(33), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(48), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(64), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(96), access: PageAccess.Inaccessible)]
  for page in 0..<original.len:
    # Nonzero canaries make a missed full-region copy observable outside the written scalar.
    for offset in 0..<4096: original[page].bytes[offset] = byte((offset*7+page*31) mod 251)
  for offset in 0..<8: original[2].bytes[offset] = byte(offset+1)
  let initial = MachineInfo(gas: MachineGas(10000))
  var current = newFlatFrame(plan, original, initial)
  runFlat(current, 20)
  assert current.reason == StepError.None and current.exit == StepExit.Host
  let held = observeFlatHostMemory(current)
  extraLifecyclePages(held, original)
  var expected = original
  expected[2].bytes[0] = 0xd1
  expected[4].bytes[6] = 0xe1
  let firstResult = withReplacedPages(held, [expected[2], expected[4]])
  assert firstResult.error == MachineError.None
  let first = firstResult.value
  let lazyStopped = current.info
  assert resumeFlatHostMemory(current, first, lazyStopped.gas, lazyStopped.registers) == StepError.None
  assert flatHostStats(current) == [1'u64, 0, 0], "lazy host updates accept without payload copies"
  extraLifecyclePages(flatMemorySnapshot(current), expected)
  checkFlatSource(current, expected)
  runFlat(current, 20)
  assert current.reason == StepError.None and current.exit == StepExit.Host
  assert uint64(current.info.registers[7]) == 0x08070605040302d1'u64
  assert uint64(current.info.registers[11]) == 0xe1
  expected[2].bytes[4095] = 0x78
  for offset, value in [0x56'u8, 0x34, 0x12, 0, 0, 0, 0]: expected[3].bytes[offset] = value
  let scalar = observeFlatHostScalars(current)
  let guest = flatMemorySnapshot(current)
  extraLifecyclePages(guest, expected)
  assert resumeFlatHostScalars(current, scalar.gas, scalar.registers) == StepError.None
  assert flatHostStats(current) == [2'u64, 0, 0]
  runFlat(current, 20)
  assert current.reason == StepError.None and current.exit == StepExit.Host
  let checkpoint = observeFlatHostMemory(current)
  extraLifecyclePages(checkpoint, expected)
  expected[3].bytes[19] = 0xa5
  expected[4].bytes[6] = 0xf2
  let posteriorResult = withReplacedPages(checkpoint, [expected[3], expected[4]])
  assert posteriorResult.error == MachineError.None
  let posterior = posteriorResult.value
  let materializedStopped = current.info
  assert resumeFlatHostMemory(current, posterior, materializedStopped.gas,
    materializedStopped.registers) == StepError.None
  assert flatHostStats(current) == [3'u64, 0, 1], "only materialized extra receives a physical page copy"
  checkFlatSource(current, expected)
  runFlat(current, 20)
  assert current.reason == StepError.None and current.exit == StepExit.Host
  assert uint64(current.info.registers[8]) == 0x12345678'u64
  assert uint64(current.info.registers[9]) == 0xf2 and uint64(current.info.registers[10]) == 0xa5
  extraLifecyclePages(flatMemorySnapshot(current), expected)
  extraLifecyclePages(held, original)
  var firstExpected = original
  firstExpected[2].bytes[0] = 0xd1
  firstExpected[4].bytes[6] = 0xe1
  extraLifecyclePages(first, firstExpected)
  firstExpected[2].bytes[4095] = 0x78
  for offset, value in [0x56'u8, 0x34, 0x12, 0, 0, 0, 0]: firstExpected[3].bytes[offset] = value
  extraLifecyclePages(guest, firstExpected)
  extraLifecyclePages(checkpoint, firstExpected)
  resetFlatFrame(current, initial)
  extraLifecyclePages(flatMemorySnapshot(current), expected)
  # Six accessible private extents plus all seven baseline pages are billed even with a lazy extra.
  const RetainedBytes = 13'u64*4096
  var scratch = takeFlatMemoryScratch(current, RetainedBytes)
  assert scratch != nil and flatMemoryScratchPayload(scratch) == RetainedBytes
  var incomingExpected = expected
  incomingExpected[2].bytes[0] = 0x99
  incomingExpected[4].bytes[6] = 0xb3
  let incomingResult = withReplacedPages(posterior, [incomingExpected[2], incomingExpected[4]])
  assert incomingResult.error == MachineError.None
  let incoming = incomingResult.value
  var reused = false
  var prepared = prepareReusedFlatMemoryFrame(plan, incoming, initial, scratch, reused)
  assert prepared.error == FlatError.None and reused and scratch == nil
  var next = takeValue(prepared)
  runFlat(next, 20)
  assert next.reason == StepError.None and next.exit == StepExit.Host
  let restored = observeFlatHostMemory(next)
  extraLifecyclePages(restored, incomingExpected)
  checkFlatSource(next, incomingExpected)
  assert flatHostStats(next) == [0'u64, 0, 0]
  let restoredCpu = next.info
  assert resumeFlatHostMemory(next, restored, restoredCpu.gas, restoredCpu.registers) == StepError.None
  runFlat(next, 20)
  assert next.reason == StepError.None and next.exit == StepExit.Host
  # Both guest loads precede the store: stale materialized bytes or a stale lazy baseline change registers.
  assert uint64(next.info.registers[7]) == 0x0807060504030299'u64
  assert uint64(next.info.registers[11]) == 0xb3
  extraLifecyclePages(flatMemorySnapshot(next), incomingExpected)
  checkFlatSource(next, incomingExpected)
  extraLifecyclePages(restored, incomingExpected)
  extraLifecyclePages(held, original)
  extraLifecyclePages(posterior, expected)

posteriorOwnerReentry()
extraOwnerLifecycle()

echo "PASS typed plan/frame limits / consumed results / exact suffix nodes / sticky refusal / jump policy / preparation spans / host retry"
