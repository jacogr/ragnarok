# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative runtime fixture for local stepping-result success preconditions.
## The executable selects a failure by command-line argument and attempts forbidden result access.

import std/[cmdline, assertions]
import ../../src/pvm/[program, machine]
import ../../src/pvm/gas/gas
import ../../src/pvm/step
proc requirePremise(accepted: bool) =
  ## Refuse a wrong setup/state with status 2; expose no compiler postcondition that folds the negative access.
  if not accepted: quit 2

proc runFailureProbe*(selection: string) =
  ## Execute exactly one argv-selected probe; the caller retains separate process isolation.
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
    let decoded = decodeProgram(bytes, pc, ProgramByteLimit(32), JumpCountLimit(0))
    assert decoded.error == ProgramError.None # A setup refusal is not the intended step rejection.
    let owner = decoded.value
    let capturedMemory = captureMemory([], PageLimit(0))
    assert capturedMemory.error == MachineError.None
    let memory = capturedMemory.value
    let info = MachineInfo(pc: pc, gas: MachineGas(1000), blockCharged: false,
      registers: default(RegisterFile))
    let capturedMachine = captureMachine(owner, memory, info)
    assert capturedMachine.error == MachineError.None
    let source = capturedMachine.value
    outcome = stepRegisters(source, GasCycleLimit(if selection == "limit": 0 elif selection ==
        "scan_limit": 4 else: 1000))
  else:
    # The uninitialized alternative never contains a guest outcome or machine handle.
    discard
  if selection == "negative":
    requirePremise(outcome.error == StepError.None)
    assert outcome.value.exit == StepExit.Continued # The same binary must accept the approved former-gate program.
    assert uint64(machineInfo(outcome.value.machine).value.pc) == 3
    assert uint64(machineInfo(outcome.value.machine).value.registers[0]) == 7
  else:
    # Establish the exact intended refusal before deliberately selecting its forbidden payload.
    case selection
    of "default": requirePremise(outcome.error == StepError.Uninitialized)
    of "invalid": requirePremise(outcome.error == StepError.InvalidMachine)
    of "unsupported": requirePremise(outcome.error == StepError.UnsupportedInstruction)
    of "limit", "scan_limit": requirePremise(outcome.error == StepError.GasCycleLimitExceeded)
    else: quit 2 # Unknown trusted modes must never resemble a passing contract probe.
    discard outcome.value # Only the intended refusal reaches the expected success precondition.

when isMainModule:
  # Standalone reproduction keeps its original command-line selection.
  runFailureProbe(paramStr(1))
