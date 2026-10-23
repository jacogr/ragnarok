# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Logical checkpoints preserve exact prior/posterior/finality provenance and detached byte ownership after original fixture scopes retire.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_supplied_context]
import ../../../src/app/logical_checkpoint
import ../../../src/state/[current_logical, current_checkpoint, checkpoint,
    accumulation_current_update, store]
import ../../../src/codec/bounded
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
