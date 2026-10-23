# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed logical checkpoint capture preserves actual post-collection source, no-finality distinction and detached bytes after joined shutdown.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[collected_native_context, collected_logical_services_context, managed_supplied_context]
import ../../../src/app/[services, logical_checkpoint, current_block_input]
import ../../../src/state/[current_logical, current_checkpoint, accumulation_current_update, store]
import ../../../src/codec/bounded
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
