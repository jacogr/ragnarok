# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated failed-result probes for host-aware instruction, dispatch and response refusals.
## The command-line selector chooses one failure before attempting forbidden value extraction.

import std/cmdline
import ../../src/pvm/[program, machine]
import ../../src/pvm/gas/gas
import ../../src/pvm/step

# Trusted handler records invocation and optionally returns an invalid default reply.
proc reply(context: var int, stopped: StepOutcome): HostResponse {.raises: [].} =
  inc context
  if paramStr(1) == "response":
    # A malformed trusted reply must not expose successful execution state.
    return default(HostResponse)
  HostResponse(action: HostAction.Continue, gas: MachineGas(0),
    registers: machineInfo(stopped.machine).value.registers, memory: memoryOf(
        stopped.machine).value)

let code = decodeProgram([0'u8, 0, 4, 10, 7, 50, 0, 5], CodeAddress(0),
  ProgramByteLimit(8), JumpCountLimit(0)).value
var cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(10), blockCharged: true,
  registers: default(RegisterFile))
cpu.registers[0] = RegisterValue(0xffff0000'u64)
let source = captureMachine(code, captureMemory([], PageLimit(0)).value, cpu).value
var context = 0
let calls = (if paramStr(1) == "calls": HostCallLimit(0) else: HostCallLimit(1))
let steps = (if paramStr(1) == "steps": ExecutionStepLimit(1) else: ExecutionStepLimit(2))
discard executeWithHost(source, context, reply, steps, calls, GasCycleLimit(0)).value
