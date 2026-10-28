# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Logical checkpoints preserve exact prior/posterior/finality provenance and detached byte ownership after original fixture scopes retire.
import std/assertions
import std/syncio
import ../../support/app_collected_native_context
import ../../support/app_collected_supplied_context
import ../../../src/app/logical_checkpoint as app_logical_checkpoint
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_checkpoint as state_current_checkpoint
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
proc scoped(): CurrentUpdateCheckpoint {.raises.} =
  ## All source fixtures retire before the caller reads the retained capsule.
  let fixture = collectedNativeFixture()
  captureLogicalCheckpoint(suppliedNativeState(fixture), ByteLimit(1048576)).value
proc main() {.raises.} =
  ## Original completed full-map qualification grants serialization observations without installation or independent trust.
  let capsule = scoped()
  let info = capsule.currentCheckpointInfo.value
  assert array[32, byte](info.prior) != array[32, byte](info.posterior.root)
  let wire = capsule.copyCurrentCheckpoint(ByteLimit(info.wireBytes)).value
  assert wire.len == int(info.wireBytes)
  var changed = wire
  changed[changed.len-1] = changed[changed.len-1] xor 1
  assert capsule.copyCurrentCheckpoint(ByteLimit(info.wireBytes)).value == wire
  assert capsule.copyCurrentCheckpoint(ByteLimit(info.wireBytes-1)).error ==
      CurrentCheckpointError.LimitExceeded
  let fixture = collectedNativeFixture()
  let logical = suppliedNativeState(fixture)
  let exact = captureLogicalCheckpoint(logical, ByteLimit(info.wireBytes))
  assert exact.error == LogicalCheckpointError.None
  let short = captureLogicalCheckpoint(logical, ByteLimit(info.wireBytes-1))
  assert short.error == LogicalCheckpointError.CheckpointFailure
  assert short.checkpointFailure.encodingError == CheckpointError.LimitExceeded
  assert sameStateSnapshot(exact.value.currentCheckpointSource.value.currentUpdateState,
      logical.currentLogicalContext.value.state)
  let empty = default(CurrentLogicalState)
  assert captureLogicalCheckpoint(empty, ByteLimit(1048576)).error ==
      LogicalCheckpointError.InvalidLogical
  echo "application-logical-checkpoint: ok"
try:
  main()
except:
  quit(2) # Neither detached mutable bytes nor a default logical source can create checkpoint authority.
