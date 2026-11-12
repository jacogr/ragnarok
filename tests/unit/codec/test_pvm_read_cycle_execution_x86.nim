# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Run the shared Read ABI and saturated admission witnesses with the selected lowerer.

import ../../support/pvm_read_cycle_execution

runReadCycleExecution()
when not defined(pvmSharedReadCycleOff) and defined(pvmSharedAsyncWitness) and
    defined(pvmX86Jit) and defined(amd64) and defined(linux):
  # A lexical guard keeps Nimony from loading this enabled-only dependency in off builds.
  import ../../support/pvm_connected_read_handoff
  runTypedAuxiliaryNative()
  runConnectedReadHandoff(false)
