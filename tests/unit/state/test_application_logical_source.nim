# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed logical source observations retain the actual collected producer and full original Parameters without hashing or heavy view copies.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_supplied_context]
import ../../../src/state/[current_logical, accumulation_current_update, store]
import ../../../src/chain/parameters
import ../../../src/app/[preparation_worker, current_block_input]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Fixed source observation must not invoke any content primitive.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe hash calls only after genuine preparation and complete supplied matching have finished.
proc main() {.raises.} =
  ## The public source surface replaces consumer traversal through private qualification layers.
  let fixture = collectedNativeFixture()
  let logical = suppliedNativeState(fixture)
  let original = fixture.receipt.currentValue.value
  fail(1)
  assert sameStateSnapshot(logical.currentLogicalUpdate.value.currentUpdateState,
      original.currentUpdateState)
  let context = logical.currentLogicalContext.value
  assert sameStateSnapshot(context.state, original.currentUpdateState)
  assert context.slot == original.currentUpdateChildContext.slot
  assert context.parameters.encodeParameters == original.currentUpdateChildContext.parameters.encodeParameters
  assert logical.currentLogicalViewInfo.value.bytes == original.currentUpdateViewInfo.bytes
  assert logical.currentLogicalViewInfo.value.owners == original.currentUpdateViewInfo.owners
  let empty = default(CurrentLogicalState)
  assert empty.currentLogicalUpdate.error == CurrentLogicalError.Uninitialized
  assert empty.currentLogicalContext.error == CurrentLogicalError.Uninitialized
  assert empty.currentLogicalViewInfo.error == CurrentLogicalError.Uninitialized
  assert calls() == 0
  fail(0)
  echo "application-logical-source: ok"
try:
  main()
except:
  quit(2) # No default logical state supplies a producer, full Parameters or retention facts.
