# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Calibrate diagnostic invocation boundaries, nested callbacks, terminal replies and pair-capacity refusal.
import std/assertions
import std/syncio
import std/envvars
import ../../src/pvm/program as pvm_program
import ../../src/pvm/machine as pvm_machine
import ../../src/pvm/gas as pvm_gas
import ../../src/pvm/step as pvm_step
proc pureSource(): Machine =
  ## Two unlikely instructions and a trap have independently known opcode/pair counts with no gas work.
  let owner = decodeProgram([0'u8, 0, 3, 2, 2, 0, 7], CodeAddress(0), ProgramByteLimit(7),
      JumpCountLimit(0)).value
  captureMachine(owner, captureMemory([], PageLimit(0)).value, MachineInfo(pc: CodeAddress(0),
      gas: MachineGas(7),
    blockCharged: true, registers: default(RegisterFile))).value
proc nested(calls: var int, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Nested execution owns its own census while the outer host/jump pair retains its previous opcode.
  inc calls
  let done = execute(pureSource(), ExecutionStepLimit(3), GasCycleLimit(0))
  assert done.error == StepError.None and done.value.exit == StepExit.Panic
  let cpu = machineInfo(stopped.machine).value
  HostResponse(action: HostAction.Continue, gas: cpu.gas, registers: cpu.registers,
      memory: memoryOf(stopped.machine).value)
proc terminal(calls: var int, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## A host terminal reply closes its one-opcode census without inventing another guest instruction.
  inc calls
  let cpu = machineInfo(stopped.machine).value
  HostResponse(action: HostAction.Panic, gas: cpu.gas, registers: cpu.registers, memory: memoryOf(
      stopped.machine).value)
type Reason = enum ## The second callback API must close the same invocation-local census.
  Refused
proc nestedFallible(calls: var int, stopped: StepOutcome): HostResult[Reason] {.raises: [].} =
  ## Select exactly the same nested continuation through the typed callback boundary.
  hostSuccess[Reason](nested(calls, stopped))
proc terminalFallible(calls: var int, stopped: StepOutcome): HostResult[Reason] {.raises: [].} =
  ## Select exactly the same terminal reply through the typed callback boundary.
  hostSuccess[Reason](terminal(calls, stopped))
when defined(pvmOpcodeCensus):
  # Only the generated diagnostic snapshot exports the bounded capacity-control hook.
  let mode = getEnv("RAGNAROK_PVM_CENSUS_CONTROL")
  assert mode in ["positive", "capacity"]
  if mode == "capacity":
    # Saturation must fail before any completed diagnostic record can be reported.
    censusCapacityControl()
  else:
    for repeat in 0..<2:
      # Fresh invocations must not invent a terminal-to-start transition across their boundary.
      let done = execute(pureSource(), ExecutionStepLimit(3), GasCycleLimit(0))
      assert done.error == StepError.None and done.value.exit == StepExit.Panic
    let owner = decodeProgram([0'u8, 0, 4, 10, 7, 50, 0, 5], CodeAddress(0), ProgramByteLimit(8),
        JumpCountLimit(0)).value
    var registers = default(RegisterFile)
    registers[0] = RegisterValue(0xffff0000'u64)
    let source = captureMachine(owner, captureMemory([], PageLimit(0)).value, MachineInfo(
        pc: CodeAddress(0), gas: MachineGas(7),
      blockCharged: true, registers: registers)).value
    var calls = 0
    assert executeWithHost(source, calls, nested, ExecutionStepLimit(2), HostCallLimit(1),
        GasCycleLimit(0)).value.exit == StepExit.Halt
    assert calls == 1
    calls = 0
    assert executeWithHost(source, calls, nestedFallible, ExecutionStepLimit(2), HostCallLimit(1),
        GasCycleLimit(0)).value.exit == StepExit.Halt
    assert calls == 1
    calls = 0
    assert executeWithHost(source, calls, terminal, ExecutionStepLimit(1), HostCallLimit(1),
        GasCycleLimit(0)).value.exit == StepExit.Panic
    assert calls == 1
    calls = 0
    assert executeWithHost(source, calls, terminalFallible, ExecutionStepLimit(1), HostCallLimit(1),
        GasCycleLimit(0)).value.exit == StepExit.Panic
    assert calls == 1
    echo "PVM opcode census controls passed"
else:
  # The ordinary source tree must compile but cannot masquerade as instrumented execution.
  assert false, "opcode census control requires instrumented snapshot"
