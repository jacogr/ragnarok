# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent gas-host and unknown-call charge witnesses, including exact signed deficits.
## Covers terminal capture invariants, attempted debt resumption, host dispatch and ARC release.

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, gas, step, host_gas, output]
import ../../support/arc_evidence

# A prepaid prefix followed by ecalli and dynamic halt gives a nonzero host PC independent of charging.
proc source(available: uint64, id: byte): Machine =
  let code = decodeProgram([0'u8, 0, 5, 2, 10, id, 50, 0, 11], CodeAddress(0),
    ProgramByteLimit(9), JumpCountLimit(0)).value
  var registers = default(RegisterFile)
  for i in 0..<13:
    # Distinct register sentinels expose any mutation beyond the specified return register.
    registers[i] = RegisterValue(uint64(100 + i))
  registers[0] = RegisterValue(0xffff0000'u64)
  var page = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly,
    bytes: default(array[4096, byte]))
  page.bytes[0] = 99
  captureMachine(code, captureMemory([page], PageLimit(1)).value,
    MachineInfo(pc: CodeAddress(0), gas: MachineGas(available), gasDeficit: GasDeficit(0),
      blockCharged: true, registers: registers)).value

# Dispatch the two implemented cases; sign-extended 0xff is outside the GP host-call set.
proc dispatch(calls: var int, stopped: StepOutcome): HostResponse {.raises: [].} =
  inc calls
  let cpu = machineInfo(stopped.machine).value
  if uint64(stopped.hostCall) == 0:
    # The concrete gas host function consumes its own fixed charge after the guest block charge.
    return gasHostResponse(cpu.gas, cpu.registers, memoryOf(stopped.machine).value)
  unknownHostResponse(cpu.gas, cpu.registers, memoryOf(stopped.machine).value)

for unknown in [false, true]:
  let cost = (if unknown: 1000'u64 else: 48'u64)
  let id = (if unknown: 255'u8 else: 0'u8)
  for available in 0'u64..cost + 1:
    # Exhaust every underfunded balance and the exact/one-over boundaries using independent subtraction.
    let original = source(available, id)
    var calls = 0
    let evaluated = executeWithHost(original, calls, dispatch, ExecutionStepLimit(3),
      HostCallLimit(1), GasCycleLimit(0))
    assert evaluated.error == StepError.None and calls == 1
    let outcome = evaluated.value
    let cpu = machineInfo(outcome.machine).value
    let prior = machineInfo(original).value
    assert cpu.blockCharged
    assert pageImage(memoryOf(outcome.machine).value, PageIndex(16)).value.bytes[0] == 99
    assert pageImage(memoryOf(outcome.machine).value, PageIndex(16)).value.access ==
        PageAccess.ReadOnly
    if available < cost:
      # Host underflow retains the causing PC and full deficit without wrapping into executable credit.
      assert outcome.exit == StepExit.OutOfGas and uint64(cpu.pc) == 1
      assert uint64(cpu.gas) == 0 and uint64(cpu.gasDeficit) == cost - available
      assert stepOnce(outcome.machine, GasCycleLimit(0)).error == StepError.InvalidMachine
      assert execute(outcome.machine, ExecutionStepLimit(0), GasCycleLimit(0)).error ==
          StepError.InvalidMachine
    else:
      # The exact cost leaves zero gas but the prepaid guest suffix still halts successfully.
      assert outcome.exit == StepExit.Halt and uint64(cpu.pc) == 0
      assert uint64(cpu.gas) == available - cost and uint64(cpu.gasDeficit) == 0
    for i in 0..<13:
      # Unknown dispatch always assigns WHAT; Omega_G mutates r7 only after an affordable charge.
      let expected = (if i == 7 and unknown: high(uint64) - 1
        elif i == 7 and available >= cost: available - cost else: uint64(prior.registers[i]))
      assert uint64(cpu.registers[i]) == expected
    assert uint64(machineInfo(original).value.gas) == available
    assert uint64(machineInfo(original).value.gasDeficit) == 0

# An initially uncharged block and the gas host each debit exactly once, with no suffix recharge.
block:
  let prepaid = source(10000, 0)
  let code = programOf(prepaid).value
  var cpu = machineInfo(prepaid).value
  cpu.blockCharged = false
  let original = captureMachine(code, memoryOf(prepaid).value, cpu).value
  let price = uint64(blockGas(code, CodeAddress(0), GasCycleLimit(1000)).value)
  var calls = 0
  let halted = executeWithHost(original, calls, dispatch, ExecutionStepLimit(3), HostCallLimit(1),
    GasCycleLimit(1000)).value
  assert halted.exit == StepExit.Halt and calls == 1
  let final = machineInfo(halted.machine).value
  assert uint64(final.gas) == 10000 - price - 48 and uint64(final.gasDeficit) == 0
  assert uint64(final.registers[7]) == 10000 - price - 48

# Full unsigned input gas is preserved without narrowing through int64 when computing a funded reply.
for available in [0x8000000000000000'u64, high(uint64)]:
  let original = source(available, 0)
  let cpu = machineInfo(original).value
  let response = gasHostResponse(cpu.gas, cpu.registers, memoryOf(original).value)
  assert uint64(response.gas) == available - 48 and uint64(response.gasDeficit) == 0
  assert uint64(response.registers[7]) == available - 48

let original = source(10000, 0)
let stopped = execute(original, ExecutionStepLimit(2), GasCycleLimit(0)).value
let cpu = machineInfo(stopped.machine).value
let memory = memoryOf(stopped.machine).value
let code = programOf(stopped.machine).value
for deficit in [1'u64, 0x8000000000000000'u64]:
  var info = cpu
  info.gas = MachineGas(0)
  info.gasDeficit = GasDeficit(deficit)
  assert captureMachine(code, memory, info).error == MachineError.InvalidGasState
  let terminal = captureTerminalMachine(code, memory, info)
  assert terminal.error == MachineError.None
  assert uint64(machineInfo(terminal.value).value.gasDeficit) == deficit
  var forged = stopped
  forged.machine = terminal.value
  let response = gasHostResponse(MachineGas(100), cpu.registers, memory)
  assert applyHostResponse(forged, response).error == StepError.InvalidMachine
  for action in [HostAction.Continue, HostAction.Halt, HostAction.Panic]:
    # A negative response cannot be made executable or successful by choosing another action.
    let bad = HostResponse(action: action, gas: MachineGas(0), gasDeficit: GasDeficit(deficit),
      registers: cpu.registers, memory: memory)
    assert applyHostResponse(stopped, bad).error == StepError.InvalidHostResponse
for deficit in [1'u64, 0x8000000000000001'u64, high(uint64)]:
  var info = cpu
  info.gas = MachineGas(if deficit == 1: 1'u64 else: 0'u64)
  info.gasDeficit = GasDeficit(deficit)
  assert captureTerminalMachine(code, memory, info).error == MachineError.InvalidGasState
  let bad = HostResponse(action: HostAction.OutOfGas, gas: info.gas, gasDeficit: info.gasDeficit,
    registers: cpu.registers, memory: memory)
  assert applyHostResponse(stopped, bad).error == StepError.InvalidHostResponse

# Halt metadata cannot be paired with a replaced negative-gas terminal owner to extract output.
var halt = execute(source(10000, 0), ExecutionStepLimit(2), GasCycleLimit(0)).value
halt = applyHostResponse(halt, HostResponse(action: HostAction.Halt, gas: MachineGas(0),
  gasDeficit: GasDeficit(0), registers: cpu.registers, memory: memory)).value
var negative = cpu
negative.gas = MachineGas(0)
negative.gasDeficit = GasDeficit(1)
halt.machine = captureTerminalMachine(code, memory, negative).value
assert captureOutput(halt, OutputByteLimit(0)).error == OutputError.InvalidMachine

# Complete funded/underfunded invocations retain neither response snapshots nor callback histories.
proc cycle() =
  for available in [0'u64, 48'u64]:
    # Both paths own immutable roots and release all transient host state on return.
    var calls = 0
    let outcome = executeWithHost(source(available, 0), calls, dispatch, ExecutionStepLimit(3),
      HostCallLimit(1), GasCycleLimit(0)).value
    assert calls == 1
    assert outcome.exit == (if available == 0: StepExit.OutOfGas else: StepExit.Halt)

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Signed terminal balances are plain values and cannot introduce an ARC ownership cycle.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_host_gas", 1000, before, after)
echo "PVM host gas passed"
echo "ARC_RELEASE cycles=1000 unchanged"
