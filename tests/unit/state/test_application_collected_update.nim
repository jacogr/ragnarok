# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared exact receipt admission refuses stale and foreign physical chains without losing the original prepared owner.
import std/[assertions, syncio]
import ../../support/collected_native_context
import ../../../src/app/collected/update as collected_update
import ../../../src/app/[chain, preparation_worker]
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/app/candidate
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/store
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
