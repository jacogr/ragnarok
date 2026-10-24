# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real guest-loop differential and timing probe; production execution remains untouched.
import std/[assertions, syncio, monotimes, envvars]
import ../../src/codec/natural
import ../../src/pvm/[program, machine, gas]
import ../../src/pvm/step as reference
import ../../build/pvm-ir-experiment/prepared_step as prepared

proc cpuNanoseconds(): int64 {.importc: "pvm_ir_cpu_nanoseconds", header: "cpu_clock.h".}
  ## Read the OS process CPU clock through the existing experiment helper.

type
  Loop = object ## Validated guest code with one arithmetic block, a backedge and dynamic halt.
    owner: Program
    body, branch, halt: int
    badTarget: bool
    price, haltPrice, cycles, haltCycles: uint64
  Expected = object ## Independent oracle publishes CPU state only when error denotes success.
    error: reference.StepError
    exit: reference.StepExit
    info: MachineInfo

proc minimumCycles(owner: Program, pc: int): uint64 =
  ## Find the exact accepted simulation limit without assuming a pipeline cycle formula.
  result = 0
  for limit in 1'u64..4096'u64:
    if blockGas(owner, CodeAddress(pc), GasCycleLimit(limit)).error == GasError.None:
      return limit
  assert false

proc guest(body: int, badTarget: bool): Loop =
  ## Encode add/xor, increment r7, branch r7 < r9 back to entry, then jump through r10.
  assert body > 0 and body <= 64 and body mod 2 == 0
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for i in 0..<body:
    # Register 8 carries dependent unsigned arithmetic, including wraparound and signed immediates.
    starts.add(code.len)
    code.add(if i mod 2 == 0: 149'u8 else: 133'u8)
    code.add(0x88)
    code.add(if i mod 2 == 0: 3'u8 else: 0xa5'u8)
  starts.add(code.len)
  for value in [149'u8, 0x77'u8, 1'u8]: code.add(value)
  let branch = code.len
  starts.add(branch)
  code.add(172)
  code.add(0x97)
  let target = if badTarget: 1 else: 0
  let offset = uint64(0) - uint64(branch - target)
  for i in 0..<4: code.add(byte((offset shr (8 * i)) and 255))
  let halt = code.len
  starts.add(halt)
  code.add(50)
  code.add(10)
  let size = encode(JamNatural(code.len))
  var wire: seq[byte] = @[0'u8, 0'u8]
  for i in 0..<size.len: wire.add(size.bytes[i])
  for value in code: wire.add(value)
  var mask = newSeq[byte]((code.len + 7) div 8)
  for pc in starts:
    mask[pc div 8] = mask[pc div 8] or byte(1 shl (pc mod 8))
  for value in mask: wire.add(value)
  let decoded = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(4096), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  let owner = decoded.value
  let cycles = minimumCycles(owner, 0)
  let haltCycles = minimumCycles(owner, halt)
  result = Loop(owner: owner, body: body, branch: branch, halt: halt, badTarget: badTarget,
    price: uint64(blockGas(owner, CodeAddress(0), GasCycleLimit(cycles)).value),
    haltPrice: uint64(blockGas(owner, CodeAddress(halt), GasCycleLimit(haltCycles)).value),
    cycles: cycles, haltCycles: haltCycles)

proc source(f: Loop, iterations, balance: uint64, entry: int, charged: bool): Machine =
  ## Bind immutable source state; terminal capture also permits deliberate invalid-PC witnesses.
  var cpu = default(RegisterFile)
  for i in 0..<13: cpu[i] = RegisterValue(uint64(i) * 17)
  cpu[7] = RegisterValue(0)
  cpu[8] = RegisterValue(high(uint64) - 5)
  cpu[9] = RegisterValue(iterations)
  cpu[10] = RegisterValue(0xffff0000'u64)
  let memory = captureMemory([], PageLimit(0))
  assert memory.error == MachineError.None
  let captured = captureTerminalMachine(f.owner, memory.value, MachineInfo(pc: CodeAddress(entry),
    gas: MachineGas(balance), blockCharged: charged, registers: cpu))
  assert captured.error == MachineError.None
  result = captured.value

proc oracle(f: Loop, initial: MachineInfo, steps, cycleLimit: uint64): Expected =
  ## Model this fixed guest independently; prices come from the retained production gas module.
  var info = initial
  var remaining = steps
  while remaining > 0:
    dec remaining
    let pc = int(uint64(info.pc))
    let arithmetic = pc >= 0 and pc < f.body * 3 and pc mod 3 == 0
    let counter = pc == f.body * 3
    if not arithmetic and not counter and pc != f.branch and pc != f.halt:
      info.pc = CodeAddress(0)
      return Expected(error: reference.StepError.None, exit: reference.StepExit.Panic, info: info)
    if not info.blockCharged:
      let price = if pc == f.halt: f.haltPrice else: f.price
      let neededCycles = if pc == f.halt: f.haltCycles else: f.cycles
      if cycleLimit < neededCycles:
        return Expected(error: reference.StepError.GasCycleLimitExceeded)
      if uint64(info.gas) < price:
        return Expected(error: reference.StepError.None, exit: reference.StepExit.OutOfGas, info: info)
      info.gas = MachineGas(uint64(info.gas) - price)
      info.blockCharged = true
    if arithmetic:
      let value = uint64(info.registers[8])
      if (pc div 3) mod 2 == 0:
        info.registers[8] = RegisterValue(value + 3)
      else:
        info.registers[8] = RegisterValue(value xor 0xffffffffffffffa5'u64)
      info.pc = CodeAddress(pc + 3)
    elif counter:
      info.registers[7] = RegisterValue(uint64(info.registers[7]) + 1)
      info.pc = CodeAddress(f.branch)
    elif pc == f.branch:
      if f.badTarget:
        info.pc = CodeAddress(0)
        return Expected(error: reference.StepError.None, exit: reference.StepExit.Panic, info: info)
      info.pc = CodeAddress(if uint64(info.registers[7]) < uint64(info.registers[
          9]): 0 else: f.halt)
      info.blockCharged = false
    else:
      info.pc = CodeAddress(0)
      return Expected(error: reference.StepError.None, exit: reference.StepExit.Halt, info: info)
  Expected(error: reference.StepError.StepLimitExceeded)

proc sameInfo(actual, expected: MachineInfo) =
  ## Compare all observable CPU fields, including the prepaid-block flag and reserved gas deficit.
  assert uint64(actual.pc) == uint64(expected.pc)
  assert uint64(actual.gas) == uint64(expected.gas)
  assert uint64(actual.gasDeficit) == uint64(expected.gasDeficit)
  assert actual.blockCharged == expected.blockCharged
  for i in 0..<13: assert uint64(actual.registers[i]) == uint64(expected.registers[i])

proc checkResult(actual: reference.StepResult, expected: Expected) =
  ## Verify the production result against the independent fixed-loop oracle.
  assert ord(actual.error) == ord(expected.error)
  if expected.error == reference.StepError.None:
    assert ord(actual.value.exit) == ord(expected.exit)
    sameInfo(machineInfo(actual.value.machine).value, expected.info)

proc checkResult(actual: prepared.StepResult, expected: Expected) =
  ## Verify the separately compiled prepared result using its own guarded result accessors.
  assert ord(actual.error) == ord(expected.error)
  if expected.error == reference.StepError.None:
    assert ord(actual.value.exit) == ord(expected.exit)
    sameInfo(machineInfo(actual.value.machine).value, expected.info)

proc checkLoops() =
  ## Cross exact gas/step/cycle boundaries, interior entries, invalid PCs and invalid branch targets.
  var cases = 0
  for body in [2, 16, 64]:
    for invalid in [false, true]:
      let f = guest(body, invalid)
      for charged in [false, true]:
        for entry in [0, 3, f.branch, f.halt, 1, f.halt + 2]:
          for balance in [0'u64, f.price - 1, f.price, f.price * 3 + f.haltPrice - 1, f.price * 3 + f.haltPrice]:
            let original = source(f, 3, balance, entry, charged)
            let before = machineInfo(original).value
            let plan = prepared.prepareExecution(original)
            for cycles in [0'u64, f.cycles - 1, f.cycles, 4096'u64]:
              let total = uint64((body + 2) * 3 + 1)
              for budget in [0'u64, 1'u64, total - 1, total, total + 1]:
                let expected = oracle(f, before, budget, cycles)
                checkResult(reference.execute(original, reference.ExecutionStepLimit(budget),
                  GasCycleLimit(cycles)), expected)
                checkResult(prepared.executePrepared(plan, prepared.ExecutionStepLimit(budget),
                  GasCycleLimit(cycles)), expected)
                sameInfo(machineInfo(original).value, before)
                inc cases
      echo "FIXTURE,", body, ",", invalid, ",", f.price, ",", f.haltPrice, ",", f.cycles
  for body in [2, 16, 64]:
    # Invalid static destinations must panic even when the branch condition would be false.
    let f = guest(body, true)
    let original = source(f, 0, f.price + f.haltPrice, 0, false)
    let before = machineInfo(original).value
    let expected = oracle(f, before, uint64(body + 3), 4096)
    assert expected.error == reference.StepError.None and expected.exit == reference.StepExit.Panic
    checkResult(reference.execute(original, reference.ExecutionStepLimit(body + 3), GasCycleLimit(
        4096)), expected)
    let plan = prepared.prepareExecution(original)
    checkResult(prepared.executePrepared(plan, prepared.ExecutionStepLimit(body + 3), GasCycleLimit(
        4096)), expected)
    sameInfo(machineInfo(original).value, before)
    inc cases
  let absent = default(Machine)
  let empty = prepared.prepareExecution(absent)
  assert reference.execute(absent, reference.ExecutionStepLimit(0), GasCycleLimit(0)).error ==
    reference.StepError.InvalidMachine
  assert prepared.executePrepared(empty, prepared.ExecutionStepLimit(0), GasCycleLimit(0)).error ==
    prepared.StepError.InvalidMachine
  echo "CHECK,", cases

proc sampleReference(original: Machine, steps: uint64, batch: int,
    expected: Expected): array[2, int64] =
  ## Retain each observed snapshot during timing, then validate it outside both clocks.
  var observed = newSeq[reference.StepResult](batch)
  let wallStart = getMonoTime().ticks
  let cpuStart = cpuNanoseconds()
  for i in 0..<batch:
    observed[i] = reference.execute(original, reference.ExecutionStepLimit(steps), GasCycleLimit(4096))
  let cpuElapsed = cpuNanoseconds() - cpuStart
  let wallElapsed = getMonoTime().ticks - wallStart
  for actual in observed: checkResult(actual, expected)
  result = [wallElapsed, cpuElapsed]

proc samplePrepared(original: Machine, plan: prepared.PreparedExecution, steps: uint64,
    batch: int, cold: bool, expected: Expected): array[2, int64] =
  ## Include preparation and table disposal on the cold path; reuse immutable operands otherwise.
  var observed = newSeq[prepared.StepResult](batch)
  let wallStart = getMonoTime().ticks
  let cpuStart = cpuNanoseconds()
  for i in 0..<batch:
    if cold:
      observed[i] = prepared.executePrepared(prepared.prepareExecution(original),
        prepared.ExecutionStepLimit(steps), GasCycleLimit(4096))
    else:
      observed[i] = prepared.executePrepared(plan, prepared.ExecutionStepLimit(steps),
          GasCycleLimit(4096))
  let cpuElapsed = cpuNanoseconds() - cpuStart
  let wallElapsed = getMonoTime().ticks - wallStart
  for actual in observed: checkResult(actual, expected)
  result = [wallElapsed, cpuElapsed]

proc benchmark() =
  ## Compare real execution with identical pricing/publication, both warm and preparation-inclusive.
  for body in [2, 16, 64]:
    let f = guest(body, false)
    for iterations in [1'u64, 10000'u64]:
      let balance = iterations * f.price + f.haltPrice + 7
      let original = source(f, iterations, balance, 0, false)
      let before = machineInfo(original).value
      let steps = iterations * uint64(body + 2) + 1
      let expected = oracle(f, before, steps, 4096)
      assert expected.error == reference.StepError.None and expected.exit == reference.StepExit.Halt
      assert uint64(expected.info.gas) == 7
      let plan = prepared.prepareExecution(original)
      let batch = if iterations == 1: 1000 else: 3
      echo "LAYOUT,", body, ",", prepared.preparedBytes(plan)
      for sample in 0..<13:
        for order in 0..<3:
          let mode = (sample + order) mod 3
          let timing = if mode == 0:
            sampleReference(original, steps, batch, expected)
            else: samplePrepared(original, plan, steps, batch, mode == 2, expected)
          sameInfo(machineInfo(original).value, before)
          if sample >= 3:
            echo "LOOP,", body, ",", iterations, ",", mode, ",", sample - 3,
              ",", timing[0], ",", timing[1], ",", batch

if getEnv("PVM_IR_ASSERT_PROBE") == "1":
  # The runner verifies this sentinel fails before any timings can be accepted.
  assert false, "pvm-ir loop assertion control"
checkLoops()
benchmark()
