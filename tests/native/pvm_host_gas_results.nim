# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated invalid gas-state/result selection probes for terminal debt and response application.
## Each command selects one refusal and attempts its forbidden success payload.

import std/cmdline
import ../../src/pvm/program as pvm_program
import ../../src/pvm/machine as pvm_machine
import ../../src/pvm/gas as pvm_gas
import ../../src/pvm/step as pvm_step
let code = decodeProgram([0'u8, 0, 4, 10, 0, 50, 0, 5], CodeAddress(0),
  ProgramByteLimit(8), JumpCountLimit(0)).value
let memory = captureMemory([], PageLimit(0)).value
var cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(0), gasDeficit: GasDeficit(0),
  blockCharged: true, registers: default(RegisterFile))
let source = captureMachine(code, memory, cpu).value
cpu.gasDeficit = GasDeficit(1)
case paramStr(1)
of "capture":
  # Executable capture cannot admit a negative balance.
  discard captureMachine(code, memory, cpu).value
of "balance":
  # Credit and debt cannot simultaneously represent a canonical terminal balance.
  cpu.gas = MachineGas(1)
  discard captureTerminalMachine(code, memory, cpu).value
of "resume":
  # Terminal negative state cannot be used as a fresh guest invocation.
  discard execute(captureTerminalMachine(code, memory, cpu).value, ExecutionStepLimit(1),
    GasCycleLimit(0)).value
else:
  # Continuing with a negative host response must expose no successful machine snapshot.
  let stopped = execute(source, ExecutionStepLimit(1), GasCycleLimit(0)).value
  discard applyHostResponse(stopped, HostResponse(action: HostAction.Continue, gas: MachineGas(0),
    gasDeficit: GasDeficit(1), registers: cpu.registers, memory: memory)).value
