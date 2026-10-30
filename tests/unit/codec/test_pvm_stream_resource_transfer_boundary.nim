# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Conditional and dynamic control transfers preserve local preparation refusals rather than guest panic.
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


let cycles = GasCycleLimit(100000)
let empty = captureMemory([], PageLimit(0)).value
var regs = default(RegisterFile)
regs[0] = RegisterValue(0xffff0000'u64)
let branchSource = owner([@[81'u8, 0x11, 0, 9, 0, 0, 0], @[50'u8, 0], @[50'u8, 0]])
for selected in [0'u64, 1'u64]:
  regs[1] = RegisterValue(selected)
  let info = MachineInfo(gas: MachineGas(1000), registers: regs)
  let expected = execute(captureMachine(branchSource, empty, info).value, ExecutionStepLimit(64), cycles)
  assert expected.error == StepError.None and expected.value.exit == StepExit.Halt
  for ceiling in [2'u64, 4'u64]:
    # Both selected outcomes use valid targets; either first-arm or second-arm admission can refuse locally.
    var limits = defaultFlatLimits()
    limits.nodes = FlatNodeLimit(ceiling)
    var prepared = prepareFlatPlan(branchSource, cycles, limits)
    assert prepared.error == FlatError.None
    let plan = takeValue(prepared)
    var frame = newFlatFrame(plan, [], info)
    runFlat(frame, 64)
    assert frame.reason == StepError.InvalidPreparedProgram and frame.exit == StepExit.Continued
    assert preparationError(frame) == FlatError.StreamLimitExceeded
    assert uint64(flatNodes(frame)) == ceiling and flatPreparationUnits(frame) == ceiling
    assert uint64(frame.info.registers[1]) == selected
  var limits = defaultFlatLimits()
  limits.nodes = FlatNodeLimit(6)
  limits.preparation = FlatPreparationLimit(4)
  var prepared = prepareFlatPlan(branchSource, cycles, limits)
  let plan = takeValue(prepared)
  var frame = newFlatFrame(plan, [], info)
  runFlat(frame, 64)
  assert frame.reason == StepError.InvalidPreparedProgram and frame.exit == StepExit.Continued
  assert preparationError(frame) == FlatError.PreparationLimitExceeded
  assert flatNodes(frame) == 4 and flatPreparationUnits(frame) == 4

# A genuine dynamic ordinal resolves a valid block; exhaustion must be distinguishable from invalid guest jump alignment/table membership.
let dynamicSource = owner([@[50'u8, 1], @[50'u8, 0]], [2'u32])
regs[1] = RegisterValue(2)
let info = MachineInfo(gas: MachineGas(1000), registers: regs)
let expected = execute(captureMachine(dynamicSource, empty, info).value, ExecutionStepLimit(64), cycles)
assert expected.error == StepError.None and expected.value.exit == StepExit.Halt
for resource in 0..1:
  var limits = defaultFlatLimits()
  limits.nodes = FlatNodeLimit(if resource == 0: 2'u64 else: 4'u64)
  limits.preparation = FlatPreparationLimit(if resource == 0: 100'u64 else: 2'u64)
  var prepared = prepareFlatPlan(dynamicSource, cycles, limits)
  let plan = takeValue(prepared)
  var frame = newFlatFrame(plan, [], info)
  runFlat(frame, 64)
  assert frame.reason == StepError.InvalidPreparedProgram and frame.exit == StepExit.Continued
  assert preparationError(frame) == (if resource ==
      0: FlatError.StreamLimitExceeded else: FlatError.PreparationLimitExceeded)
  assert flatNodes(frame) == 2 and flatPreparationUnits(frame) == 2
  assert uint64(frame.info.registers[1]) == 2

echo "PASS valid conditional arms / both outcomes / dynamic targets / node and preparation refusals stay local"
