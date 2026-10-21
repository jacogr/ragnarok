# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative runtime fixture for local stepping-result success preconditions.
## The executable selects a failure by command-line argument and attempts forbidden result access.

import std/[cmdline, assertions]
import ../../src/pvm/[program, machine, gas, step]
let selection = paramStr(1)
var outcome = default(StepResult)
# Runtime selection prevents constant folding from substituting a different rejection mechanism.
if selection == "invalid":
  outcome = stepRegisters(default(Machine), GasCycleLimit(100))
elif selection != "default":
  # A short load/trap program supplies valid snapshots for scope and budget failures.
  var bytes = @[0'u8, 0, 3, 51, 0, 0, 5]
  var pc = CodeAddress(0)
  if selection == "unsupported":
    # Executing the trap is outside this bounded register-only API.
    pc = CodeAddress(2)
  elif selection in ["negative", "scan_limit"]:
    # The former negative target now prices successfully; a short scan limit still refuses before the first mutation.
    bytes = @[0'u8, 0, 6, 51, 0, 7, 170, 0, 252, 9]
  let owner = decodeProgram(bytes, pc, ProgramByteLimit(32), JumpCountLimit(0)).value
  let memory = captureMemory([], PageLimit(0)).value
  let info = MachineInfo(pc: pc, gas: MachineGas(1000), blockCharged: false,
    registers: default(RegisterFile))
  let source = captureMachine(owner, memory, info).value
  outcome = stepRegisters(source, GasCycleLimit(if selection == "limit": 0 elif selection ==
      "scan_limit": 4 else: 1000))
else:
  # The uninitialized alternative never contains a guest outcome or machine handle.
  discard
if selection == "negative":
  assert outcome.value.exit == StepExit.Continued # The same binary must accept the approved former-gate program.
  assert uint64(machineInfo(outcome.value.machine).value.pc) == 3
  assert uint64(machineInfo(outcome.value.machine).value.registers[0]) == 7
else:
  discard outcome.value # Declared local failures must still enforce the checked success precondition.
