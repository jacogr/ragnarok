# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Typed local preparation limits, exact cache admission and repairable host refusals.
import std/[assertions, syncio]
import ../../../src/pvm/internal/handler_stream
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine, gas, step]
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
assert hostWork == 4
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
assert flatPreparationUnits(hostFrame) == 7
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
assert flatPreparationUnits(hostFrame) == 7 and flatHostStats(hostFrame)[1] == 1
assert pageImage(replacementObservation, PageIndex(16)).value.bytes[0] == 77
assert pageImage(flatMemorySnapshot(hostFrame), PageIndex(17)).value.bytes == images[1].bytes
checkFlatSource(hostFrame)
let invalidMemory = default(Memory)
assert memoryPageCount(invalidMemory).error == MachineError.InvalidOwner
assert uint32(memoryPageCount(observation).value) == 1

echo "PASS typed plan/frame limits / consumed results / exact suffix nodes / sticky refusal / jump policy / preparation spans / host retry"
