# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated output-result failure probes for default, nonhalt, invalid owner and budget refusal.
## Each selected failure attempts the success-only byte accessor and must trap its contract.

import std/cmdline
import ../../src/pvm/[program, machine, initialize, gas, step, output]
let selection = paramStr(1)
var result = default(OutputResult)
# Default has no byte value; all other cases exercise a real API refusal.
if selection == "nonhalt":
  let pending = default(StepOutcome)
  result = captureOutput(pending, OutputByteLimit(0))
elif selection == "invalid" or selection == "limit":
  # Standard initialization supplies a real one-byte argument and the halt return-address register.
  let source = initializeMachine([0'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0,
    0, 0, 2, 50, 0, 1], [9'u8], CodeAddress(0), MachineGas(100),
    InitializationLimits(envelope: InitializationByteLimit(21), program: ProgramByteLimit(6),
      jumps: JumpCountLimit(0), pages: PageLimit(1))).value
  var outcome = execute(source, ExecutionStepLimit(1), GasCycleLimit(100)).value
  if selection == "invalid":
    # A replaced public handle must never permit access through a stale halted discriminator.
    outcome.machine = default(Machine)
  result = captureOutput(outcome, OutputByteLimit(0))
else:
  # Leave the default local failure selected, without inventing any guest outcome.
  discard
discard result.value
