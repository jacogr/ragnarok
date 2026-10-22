# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Host-response failure and exit-metadata contract probes selected by command-line arguments.
## Each invocation attempts exactly one forbidden result or metadata access.

import std/[assertions, cmdline]
import ../../src/pvm/[program, machine, initialize, gas, step]
let selection = paramStr(1)
let accessor = paramStr(2)
let source = initializeMachine([0'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0,
  0, 0, 5, 2, 10, 7, 50, 0, 11], [], CodeAddress(0), MachineGas(10000),
  InitializationLimits(envelope: InitializationByteLimit(24), program: ProgramByteLimit(9),
    jumps: JumpCountLimit(0), pages: PageLimit(0))).value
var host = execute(source, ExecutionStepLimit(2), GasCycleLimit(1000)).value
var response = HostResponse(action: HostAction.Continue, gas: MachineGas(0),
  registers: machineInfo(host.machine).value.registers, memory: memoryOf(host.machine).value)
case selection
of "default":
  # Default responses are not silently treated as continuations.
  response = default(HostResponse)
of "nonhost":
  # A default outcome has no host identifier or causing instruction.
  host = default(StepOutcome)
of "memory":
  # All posterior actions require a real immutable memory owner.
  response.memory = default(Memory)
of "machine":
  # Replacing a public snapshot handle must not bypass owner validation.
  host.machine = default(Machine)
of "halt":
  # Removed host Halt is rejected before any successful outcome can be selected.
  response.action = HostAction.Halt
of "panic":
  # Host panic is still a completed response, not a local failure payload.
  response.action = HostAction.Panic
of "oog":
  # Host out-of-gas does not carry a fault page or host identifier.
  response.action = HostAction.OutOfGas
else:
  # The continue witness publishes an ordinary Continued outcome without exit metadata.
  discard
let applied = applyHostResponse(host, response)
if selection == "halt":
  assert applied.error == StepError.InvalidHostResponse,
      "current host Halt is an invalid response" # The following value access must fail at the result guard.
if accessor == "host":
  # Successful continue/panic/OOG responses reject stale host metadata; rejected Halt has no value.
  discard applied.value.hostCall
elif accessor == "fault":
  # No host-response action can manufacture a guest fault page.
  discard applied.value.faultPage
else:
  # Local failures must reject success-state extraction entirely.
  discard applied.value
