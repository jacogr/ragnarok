# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Common full-invocation owner record, shared with the native qualification witness.

from ../../src/pvm/step import PreparedInfo

proc invocationOwnerRecord*(native: PreparedInfo, label: string): string =
  ## Serialize the common async owner's copied physical counters on either ISA.
  "ARM_OWNER," & label & "," & $native.nativeFragments & "," & $native.nativeCalls & "," &
    $native.nativeOperations & "," & $native.nativeCodeBytes & "," & $native.nativeCompilationNs &
    "," & $native.nativeBranchCalls & "," & $native.nativeHeaderCalls
