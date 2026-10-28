# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared exact receipt admission refuses stale and foreign physical chains without losing the original prepared owner.
import std/assertions
import std/syncio
import ../../support/app_collected_native_context
import ../../../src/app/collected_update as app_collected_update
import ../../../src/app/chain as app_chain
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/app/candidate as app_candidate
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/store as state_store
proc main() {.raises.} =
  ## Real native collection supplies an admitted source; unchanged receipts cannot authorize another selected head.
  let fixture = collectedNativeFixture()
  let selected = captureCollectedUpdate(fixture.chain, fixture.receipt)
  assert selected.error == CollectedUpdateError.None
  assert sameStateSnapshot(selected.value.currentUpdateState,
      fixture.receipt.currentValue.value.currentUpdateState)
  let empty = default(PreparationCompletion)
  assert captureCollectedUpdate(fixture.chain, empty).error == CollectedUpdateError.NoCompletion
  let noChain = default(ApplicationChain)
  assert captureCollectedUpdate(noChain, fixture.receipt).error ==
      CollectedUpdateError.StaleUpdate
  var adopted = fixture.chain
  adopted.installPrepared(selected.value)
  assert captureCollectedUpdate(adopted, fixture.receipt).error == CollectedUpdateError.StaleUpdate
  assert captureCollectedUpdate(fixture.chain, fixture.receipt).error == CollectedUpdateError.None
  echo "application-collected-update: ok"
try:
  main()
except:
  quit(2) # Native failure is never receipt success.
