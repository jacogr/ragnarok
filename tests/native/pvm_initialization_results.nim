# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime rejection fixture for initialization success-only machine extraction.
## Selects default, malformed-envelope and local-limit failures by command-line argument.

import std/cmdline
import ../../src/pvm/[program, machine, initialize]
let selection = paramStr(1)
var outcome = default(InitializationResult)
# Every failure must reject value access rather than fabricate an executable machine.
if selection == "invalid":
  outcome = initializeMachine([], [], CodeAddress(0), MachineGas(0), default(InitializationLimits))
elif selection == "limit":
  # Any byte exceeds the zero envelope cap before parsing or allocating pages.
  outcome = initializeMachine([0'u8], [], CodeAddress(0), MachineGas(0), default(InitializationLimits))
else:
  # Default remains explicitly uninitialized even when all storage bits are zero.
  discard
discard outcome.value
