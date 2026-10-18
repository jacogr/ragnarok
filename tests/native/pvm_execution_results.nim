# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative runtime probes for host/fault metadata selection and bounded-execution local failures.
## Chooses an outcome through argv, then deliberately requests an unavailable payload.

import std/cmdline
import ../../src/pvm/[program, machine, gas, step]

let selection = paramStr(1)
var outcome = default(StepOutcome)
if selection == "invalid":
  # Missing owners are local failures; selecting their guest outcome must be rejected.
  outcome = execute(default(Machine), ExecutionStepLimit(1), GasCycleLimit(1000)).value
elif selection != "default":
  # Start with unlikely/trap; every alternate has an explicitly encoded bitmap.
  var code = @[2'u8, 0]
  var mask = 3'u8
  var registers = default(RegisterFile)
  if selection == "panic":
    # A real single-step trap carries no host-call identifier.
    code = @[0'u8]
    mask = 1
  elif selection == "halt":
    # Dynamic sentinel exit has no host metadata either.
    code = @[50'u8, 0, 0]
    mask = 5
    registers[0] = RegisterValue(0xffff0000'u64)
  elif selection == "fault":
    # An unmapped ordinary address yields a real fault with page metadata only.
    code = @[52'u8, 0, 0, 0, 1, 0, 0]
    mask = 65
  elif selection == "host-page":
    # Host metadata must not be confused with the fault-page variant.
    code = @[10'u8, 1, 0]
    mask = 5
  var bytes = @[0'u8, 0, byte(code.len)]
  # Copy the selected instruction stream before its explicit opcode mask.
  for value in code: bytes.add(value)
  bytes.add(mask)
  let program = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(32), JumpCountLimit(0)).value
  let memory = captureMemory([], PageLimit(0)).value
  let source = captureMachine(program, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(0),
    blockCharged: selection != "oog", registers: registers)).value
  if selection == "step-limit":
    # One continued instruction exhausts the local budget without creating a guest outcome.
    outcome = execute(source, ExecutionStepLimit(1), GasCycleLimit(0)).value
  else:
    # Other probes deliberately select a guest outcome before requesting the wrong metadata.
    outcome = stepOnce(source, GasCycleLimit(1000)).value
else:
  # A default outcome has neither host-call nor fault-page metadata.
  discard
if selection == "host-page":
  # This is the only probe requesting fault metadata; it must fail on the actual Host alternative.
  discard outcome.faultPage
else:
  # Every remaining successfully selected outcome is non-Host, and local failures never reach here.
  discard outcome.hostCall
