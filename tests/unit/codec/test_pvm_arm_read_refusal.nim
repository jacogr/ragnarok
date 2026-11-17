# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Incomplete ARM reads and refused child images must not publish native code.

import std/syncio
import ../../../src/pvm/internal/[arm64_jit, native_ir, native_read_body]
when NativeReadCycleEnabled:
  import ../../support/pvm_read_cycle_execution as cycle_execution

# Ordinary native read qualification must not expose the assertion-based legacy cache owner.
when declared(newArmJit):
  {.error: "legacy native owner leaked into the ordinary read profile".}

when NativeCheckedReadEnabled:
  # The real ARM read path and private malformed-metadata controls execute only on a supported native target.
  witnessArmReadGuards()
  when NativeReadCycleEnabled:
    # The complete copied fixture enters the same producer used by the native provider; failed code never executes.
    witnessArmCycleHardwareRefusal(cycle_execution.cycleFixture())
echo "PVM ARM read refusal passed"
