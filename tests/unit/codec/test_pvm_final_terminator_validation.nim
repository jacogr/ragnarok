# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Preserve GP-PVM-004's Gray Paper execution witness alongside the approved JAM preparation check.

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/step

proc witness(code: openArray[byte], terminalPc: uint64) =
  ## The legal load prefix must survive runtime panic for every structurally valid final terminator.
  var wire = @[0'u8, 0, byte(code.len)]
  for value in code:
    # Copy the literal code without invoking a production encoder to construct expectations.
    wire.add(value)
  wire.add(9)
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  var regs = default(RegisterFile)
  regs[7] = RegisterValue(99)
  let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(123), blockCharged: true,
    registers: regs)
  let memory = captureMemory([], PageLimit(1)).value
  let source = captureMachine(decoded.value, memory, info).value
  let first = stepOnce(source, GasCycleLimit(0))
  assert first.error == StepError.None and first.value.exit == StepExit.Continued
  let prefix = machineInfo(first.value.machine).value
  assert uint64(prefix.pc) == 3 and uint64(prefix.registers[7]) == 7
  assert uint64(prefix.gas) == 123 and prefix.blockCharged
  let last = stepOnce(first.value.machine, GasCycleLimit(0))
  assert last.error == StepError.None and last.value.exit == StepExit.Panic
  let terminal = machineInfo(last.value.machine).value
  assert uint64(terminal.pc) == terminalPc and uint64(terminal.registers[7]) == 7
  let completed = execute(source, ExecutionStepLimit(2), GasCycleLimit(0))
  assert completed.error == StepError.None and completed.value.exit == StepExit.Panic
  let posterior = machineInfo(completed.value.machine).value
  assert uint64(posterior.pc) == 0 and uint64(posterior.gas) == 123 and posterior.blockCharged
  for index in 0..<13:
    # Only the successful prefix writes r7; the original CPU remains untouched in every case.
    assert uint64(posterior.registers[index]) == (if index == 7: 7'u64 else: 0'u64)
    assert uint64(machineInfo(source).value.registers[index]) == uint64(regs[index])
  assert uint64(machineInfo(source).value.pc) == 0 and uint64(machineInfo(source).value.gas) == 123
  assert machineInfo(source).value.blockCharged
  assert execute(source, ExecutionStepLimit(1), GasCycleLimit(0)).error ==
      StepError.StepLimitExceeded

# The positive trap control is also accepted by the pinned PolkaVM module loader.
witness([51'u8, 7, 7, 0], 4)
# The paper admits both final opcodes as terminators; their missing successors cause runtime panic.
witness([51'u8, 7, 7, 1], 3)
witness([51'u8, 7, 7, 170, 0, 253], 3)
echo "PVM final terminator validation witnesses passed: 3; paper-aligned raw execution"
