# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Replay independent control paths, entered-block prices, invalid successors and complete CPU prefixes through every policy.

import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/[gas, plan as gas_plan, memo as gas_memo]
import ../../../src/pvm/step

proc word(data: string, at, width: int): uint64 =
  ## Read fixed little-endian fixture fields after their caller proves the complete record extent.
  result = 0
  for index in 0..<width: result = result or (uint64(byte(data[at+index])) shl (8*index))

type PriceBlock = object ## Independent prefix registers and whole-block price describe one actually entered block.
  start, charge: uint64
  registers: RegisterFile

proc verify(source: Machine, registers: RegisterFile, pc, gas: uint64,
    charged: bool, memory: Memory) =
  ## Complete CPU and memory-owner parity includes source preservation after successful and locally refused replay.
  let cpu = machineInfo(source).value
  assert uint64(cpu.pc) == pc and uint64(cpu.gas) == gas and uint64(cpu.gasDeficit) == 0
  assert cpu.blockCharged == charged and memoryOf(source).value == memory
  for i in 0..<13:
    assert uint64(cpu.registers[i]) == uint64(registers[
        i]) # Explicit load/jump aliases remain visible even on terminal failure.

proc run(source: Machine, mode: int, steps: uint64, plan: GasPlan, memo: GasMemo): StepResult =
  ## Policies share exact attempt counts; the same memo is replayed cold and warm without carrying CPU state.
  case mode
  of 0: execute(source, ExecutionStepLimit(steps), GasCycleLimit(1000))
  of 1: execute(source, ExecutionStepLimit(steps), plan)
  else: execute(source, ExecutionStepLimit(steps), memo)

var data = ""
var pricing = ""
try:
  data = readFile(getEnv("RAGNAROK_PVM_CONTROL"))
  pricing = readFile(getEnv("RAGNAROK_PVM_CONTROL_PRICING"))
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVMCTL01"
let count = int(word(data, 8, 4))
assert count >= 384 and count <= 4096
assert pricing.len >= 12 and pricing[0..7] == "PVMCPR01" and word(pricing, 8, 4) == uint64(count)
var priceCursor = 12
var cursor = 12
for row in 0..<count:
  assert data.len-cursor >= 217
  let length = int(word(data, cursor, 4))
  let exit = byte(data[cursor+4])
  let referencePc = word(data, cursor+5, 4)
  assert exit <= 1 and length <= 64
  var registers = default(RegisterFile)
  var expected = default(RegisterFile)
  for index in 0..<13:
    registers[index] = RegisterValue(word(data, cursor+9+index*8, 8))
    expected[index] = RegisterValue(word(data, cursor+113+index*8, 8))
  cursor += 217
  assert length <= data.len-cursor
  var wire = newSeq[byte](length)
  for index in 0..<length: wire[index] = byte(data[cursor+index])
  cursor += length
  assert pricing.len-priceCursor >= 10
  let steps = uint64(byte(pricing[priceCursor]))
  let total = word(pricing, priceCursor+1, 8)
  let blockCount = int(byte(pricing[priceCursor+9]))
  assert steps >= 2 and steps <= 4 and total > 0 and total < 10000 and blockCount in [1, 2]
  priceCursor += 10
  var blocks: seq[PriceBlock] = @[]
  var charged = 0'u64
  for i in 0..<blockCount:
    # Fixed dimensions bound the copied prefix registers before reading any companion field.
    assert pricing.len-priceCursor >= 116
    var item = PriceBlock(start: word(pricing, priceCursor, 4), charge: word(pricing, priceCursor+4, 8),
      registers: default(RegisterFile))
    assert item.start < 64 and item.charge > 0 and item.charge < 10000
    for r in 0..<13: item.registers[r] = RegisterValue(word(pricing, priceCursor+12+r*8, 8))
    blocks.add(item)
    charged += item.charge
    priceCursor += 116
  assert charged == total and blocks[0].start == 0
  for r in 0..<13: assert uint64(blocks[0].registers[r]) == uint64(registers[r])
  let program = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(1)).value
  let memory = captureMemory([], PageLimit(0)).value
  let source = captureMachine(program, memory,
    MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000), blockCharged: false,
      registers: registers)).value
  let answer = execute(source, ExecutionStepLimit(4), GasCycleLimit(1000))
  assert answer.error == StepError.None
  assert answer.value.exit == (if exit == 0: StepExit.Halt else: StepExit.Panic)
  assert uint64(machineInfo(answer.value.machine).value.pc) == 0
  for index in 0..<13:
    if uint64(machineInfo(answer.value.machine).value.registers[index]) != uint64(expected[index]):
      echo "control register mismatch: row=", row, " register=", index
      assert false
    assert uint64(machineInfo(source).value.registers[index]) == uint64(registers[index])
  verify(answer.value.machine, expected, 0, 10000-total, true, memory)
  let prepared = newGasPlan(program, GasPlanLimits(blocks: GasPlanBlockLimit(3),
    bytes: GasPlanByteLimit(512), cycles: GasCycleLimit(1000)))
  let learned = newGasMemo(program, GasMemoLimits(bytes: GasMemoByteLimit(512),
      cycles: GasCycleLimit(1000)))
  assert prepared.error == GasPlanError.None and learned.error == GasMemoError.None
  for item in blocks:
    assert uint64(blockGas(prepared.value, CodeAddress(item.start)).value) ==
        item.charge # Compare entered-block costs against the independent model.
  for mode in 0..<4:
    # Replaying warmed prices must preserve independent terminal mutations, full gas and both conditional-successor requirements.
    let completed = run(source, mode, steps, prepared.value, learned.value)
    assert completed.error == StepError.None and completed.value.exit == (if exit ==
        0: StepExit.Halt else: StepExit.Panic)
    verify(completed.value.machine, expected, 0, 10000-total, true, memory)
    verify(source, registers, 0, 10000, false, memory)
    let limited = run(source, mode, steps-1, prepared.value, learned.value)
    assert limited.error == StepError.StepLimitExceeded
    verify(source, registers, 0, 10000, false, memory)
    var prefix = 0'u64
    for item in blocks:
      # One-less gas refuses at each independently entered block before that block's mutations, including aliased load/jump writes.
      let budget = prefix+item.charge-1
      let short = captureMachine(program, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(
          budget),
        gasDeficit: GasDeficit(0), blockCharged: false, registers: registers)).value
      let stopped = run(short, mode, 4, prepared.value, learned.value)
      assert stopped.error == StepError.None and stopped.value.exit == StepExit.OutOfGas
      verify(stopped.value.machine, item.registers, item.start, item.charge-1, false, memory)
      verify(short, registers, 0, budget, false, memory)
      prefix += item.charge
    let paidBudget = 7+total-blocks[0].charge
    let paid = captureMachine(program, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(
        paidBudget),
      gasDeficit: GasDeficit(0), blockCharged: true, registers: registers)).value
    let terminal = run(paid, mode, steps, prepared.value, learned.value)
    assert terminal.error == StepError.None and terminal.value.exit == (if exit ==
        0: StepExit.Halt else: StepExit.Panic)
    verify(terminal.value.machine, expected, 0, 7, true, memory)
    verify(paid, registers, 0, paidBudget, true, memory)
    assert gasMemoInfo(learned.value).value.pricedBlocks == (if mode < 2: 0'u64 else: uint64(blockCount))
  var traced = source
  var stopped = false
  for attempt in 0..<4:
    # Compare the causing PC and the GP single-step PC before recursive exit normalization.
    let observed = stepOnce(traced, GasCycleLimit(1000)).value
    if observed.exit in {StepExit.Panic, StepExit.Halt}:
      assert observed.exit == (if exit == 0: StepExit.Halt else: StepExit.Panic)
      if exit == 1:
        let before = machineInfo(traced).value.pc
        let item = instruction(program, before).value
        if item.opcode == 0:
          # GP single-step trap advances by default; PolkaVM reports the causing instruction PC.
          assert uint64(before) == referencePc
          assert uint64(machineInfo(observed.machine).value.pc) == referencePc+1+uint64(item.skip)
        else:
          assert uint64(machineInfo(observed.machine).value.pc) == referencePc
      else:
        assert referencePc == 0xffffffff'u64
      stopped = true
      break
    assert observed.exit == StepExit.Continued
    traced = observed.machine
  assert stopped
  assert uint64(machineInfo(source).value.pc) == 0
  assert uint64(machineInfo(source).value.gas) == 10000 and not machineInfo(
      source).value.blockCharged
assert cursor == data.len and priceCursor == pricing.len
echo "PVM control-flow reference passed: ", count
