# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Run the shared Read ABI and saturated admission witnesses with the selected lowerer.

import ../../support/pvm_read_cycle_execution

runReadCycleExecution()
when defined(pvmSharedReadCycle) and defined(pvmSharedAsyncWitness) and
    defined(pvmX86Jit) and defined(amd64) and defined(linux):
  # Keep the handoff dependency within the profile that can publish a real image.
  import ../../support/pvm_connected_read_handoff
  runConnectedReadHandoff(false)
