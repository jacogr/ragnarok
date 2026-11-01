# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## A reused executable stream must not carry a sealed charge across pricing policies.
import std/[assertions, syncio]
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/[gas, plan as gas_plan, memo as gas_memo]
import ../../../src/pvm/step
import ../../../src/pvm/internal/handler_stream

proc newFrame(plan: FlatPlan, initial: MachineInfo): FlatFrame =
  newFlatFrame(plan, [], initial)

proc newMemo(source: Program, cycles: uint64): GasMemo =
  let created = newGasMemo(source, GasMemoLimits(bytes: GasMemoByteLimit(64),
    cycles: GasCycleLimit(cycles)))
  assert created.error == GasMemoError.None
  created.value

proc checkHalt(frame: FlatFrame, initial: MachineInfo, price: uint64) =
  assert frame.reason == StepError.None and frame.exit == StepExit.Halt
  assert uint64(frame.info.pc) == uint64(initial.pc)
  assert uint64(frame.info.gas) == uint64(initial.gas)-price
  assert frame.info.blockCharged and frame.info.registers == initial.registers

proc checkCycleRefusal(frame: FlatFrame, initial: MachineInfo) =
  assert frame.reason == StepError.GasCycleLimitExceeded and frame.exit == StepExit.Continued
  assert frame.info == initial

let decoded = decodeProgram(@[0'u8, 0, 2, 50, 0, 1], CodeAddress(0),
  ProgramByteLimit(64), JumpCountLimit(0))
assert decoded.error == ProgramError.None
let source = decoded.value
let priced = blockGas(source, CodeAddress(0), GasCycleLimit(1000))
assert priced.error == GasError.None
let price = uint64(priced.value)
assert price > 0 and price < 100
var registers = default(RegisterFile)
registers[0] = RegisterValue(0xffff0000'u64)
let initial = MachineInfo(gas: MachineGas(100), registers: registers)

var highAdmission = prepareFlatPlan(source, GasCycleLimit(1000), defaultFlatLimits(), false)
var lowAdmission = prepareFlatPlan(source, GasCycleLimit(0), defaultFlatLimits(), false)
assert highAdmission.error == FlatError.None and lowAdmission.error == FlatError.None
let highFlat = takeValue(highAdmission)
let lowFlat = takeValue(lowAdmission)
let completeResult = newGasPlan(source, GasPlanLimits(blocks: GasPlanBlockLimit(1),
  bytes: GasPlanByteLimit(64), cycles: GasCycleLimit(1000)))
assert completeResult.error == GasPlanError.None
let complete = completeResult.value

block defaultToLowMemo:
  let freshMemo = newMemo(source, 0)
  var fresh = newFrame(highFlat, initial)
  assert selectFlatPrices(fresh, default(GasPlan), freshMemo) == StepError.None
  runFlat(fresh, 1)
  checkCycleRefusal(fresh, initial)
  assert gasMemoInfo(freshMemo).value.pricedBlocks == 0

  var warm = newFrame(highFlat, initial)
  runFlat(warm, 1)
  checkHalt(warm, initial, price)
  var stream = takeFlatStream(warm)
  let switchedMemo = newMemo(source, 0)
  var switched = newFrame(highFlat, initial)
  assert selectFlatPrices(switched, default(GasPlan), switchedMemo) == StepError.None
  restoreFlatStream(switched, stream)
  runFlat(switched, 1)
  checkCycleRefusal(switched, initial)
  assert gasMemoInfo(switchedMemo).value.pricedBlocks == 0

block memoToAnotherMemo:
  let allowed = newMemo(source, 1000)
  var warm = newFrame(highFlat, initial)
  assert selectFlatPrices(warm, default(GasPlan), allowed) == StepError.None
  runFlat(warm, 1)
  checkHalt(warm, initial, price)
  assert gasMemoInfo(allowed).value.pricedBlocks == 1
  var stream = takeFlatStream(warm)
  let refused = newMemo(source, 0)
  var switched = newFrame(highFlat, initial)
  assert selectFlatPrices(switched, default(GasPlan), refused) == StepError.None
  restoreFlatStream(switched, stream)
  runFlat(switched, 1)
  checkCycleRefusal(switched, initial)
  assert gasMemoInfo(refused).value.pricedBlocks == 0

block memoToDefault:
  let allowed = newMemo(source, 1000)
  var warm = newFrame(lowFlat, initial)
  assert selectFlatPrices(warm, default(GasPlan), allowed) == StepError.None
  runFlat(warm, 1)
  checkHalt(warm, initial, price)
  var stream = takeFlatStream(warm)
  var switched = newFrame(lowFlat, initial)
  restoreFlatStream(switched, stream)
  runFlat(switched, 1)
  checkCycleRefusal(switched, initial)

block defaultToCompletePlan:
  var warm = newFrame(lowFlat, initial)
  runFlat(warm, 1)
  checkCycleRefusal(warm, initial)
  var stream = takeFlatStream(warm)
  var switched = newFrame(lowFlat, initial)
  assert selectFlatPrices(switched, complete, default(GasMemo)) == StepError.None
  restoreFlatStream(switched, stream)
  runFlat(switched, 1)
  checkHalt(switched, initial, price)

block completePlanToDefault:
  var warm = newFrame(lowFlat, initial)
  assert selectFlatPrices(warm, complete, default(GasMemo)) == StepError.None
  runFlat(warm, 1)
  checkHalt(warm, initial, price)
  var stream = takeFlatStream(warm)
  var switched = newFrame(lowFlat, initial)
  restoreFlatStream(switched, stream)
  runFlat(switched, 1)
  checkCycleRefusal(switched, initial)

block lowMemoToDefault:
  let refused = newMemo(source, 0)
  var warm = newFrame(highFlat, initial)
  assert selectFlatPrices(warm, default(GasPlan), refused) == StepError.None
  runFlat(warm, 1)
  checkCycleRefusal(warm, initial)
  var stream = takeFlatStream(warm)
  var switched = newFrame(highFlat, initial)
  restoreFlatStream(switched, stream)
  runFlat(switched, 1)
  checkHalt(switched, initial, price)

block defaultKeepsCache:
  var warm = newFrame(highFlat, initial)
  runFlat(warm, 1)
  checkHalt(warm, initial, price)
  var stream = takeFlatStream(warm)
  let nodes = streamNodes(stream)
  assert nodes > 0
  var reused = newFrame(highFlat, initial)
  restoreFlatStream(reused, stream)
  assert uint64(flatNodes(reused)) == nodes
  runFlat(reused, 1)
  checkHalt(reused, initial, price)

block latePolicySelectionRefuses:
  var warm = newFrame(highFlat, initial)
  runFlat(warm, 1)
  checkHalt(warm, initial, price)
  let refused = newMemo(source, 0)
  assert selectFlatPrices(warm, default(GasPlan), refused) == StepError.InvalidPreparedProgram
  assert gasMemoInfo(refused).value.pricedBlocks == 0

block foreignPlanStillRefuses:
  # Even dynamic prices belong to the original plan's cycle limit in a plain build.
  var otherAdmission = prepareFlatPlan(source, GasCycleLimit(0), defaultFlatLimits(), false)
  assert otherAdmission.error == FlatError.None
  let otherPlan = takeValue(otherAdmission)
  var warm = newFrame(highFlat, initial)
  runFlat(warm, 1)
  checkHalt(warm, initial, price)
  var stream = takeFlatStream(warm)
  let retained = streamNodes(stream)
  var foreign = newFrame(otherPlan, initial)
  restoreFlatStream(foreign, stream)
  assert preparationError(foreign) == FlatError.InvalidProgram
  assert streamNodes(stream) == retained

echo "PASS stream pricing owner / default memo complete-plan transitions"
