# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed logical checkpoint capture preserves actual post-collection source, no-finality distinction and detached bytes after joined shutdown.
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/app_collected_native_context
import ../../support/app_collected_logical_services_context
import ../../support/app_managed_supplied_context
import ../../../src/app/services as app_services
import ../../../src/app/logical_checkpoint as app_logical_checkpoint
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_checkpoint as state_current_checkpoint
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
proc main() {.raises.} =
  ## Actual Services preparation owns the selected prior; source extraction/copy occurs only after matching collection.
  let fixture = collectedNativeFixture()
  var owner = default(Services)
  var input = default(CurrentBlockInput)
  var path = "application-managed-logical-checkpoint-chain.json"
  discard startLogicalServices(owner, fixture.fixture, path)
  defer:
    owner.close()
    discard posix.unlink(path.toCString())
  let logical = collectManagedSupplied(owner, input, fixture.fixture)
  let capsule = owner.captureLogicalCheckpoint(logical, ByteLimit(1048576)).value
  assert sameStateSnapshot(capsule.currentCheckpointSource.value.currentUpdateState,
      logical.currentLogicalContext.value.state)
  assert capsule.currentCheckpointFinalized.error == CurrentCheckpointError.NoFinality
  let info = capsule.currentCheckpointInfo.value
  let bytes = capsule.copyCurrentCheckpoint(ByteLimit(info.wireBytes)).value
  owner.close()
  assert capsule.copyCurrentCheckpoint(ByteLimit(info.wireBytes)).value == bytes
  let empty = default(CurrentLogicalState)
  assert owner.captureLogicalCheckpoint(empty, ByteLimit(1048576)).error ==
      LogicalCheckpointError.InvalidLogical
  echo "application-managed-logical-checkpoint: ok"
try:
  main()
except:
  quit(2) # Shutdown or source errors cannot supply a successful checkpoint prefix.
