# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_transfer_arc_release"}

## Sole-owner prepared bytes survive source retirement, move exactly once and publish without graph aliases.

import std/[assertions, syncio]
import std/posix/posix
import ../../../src/state/[checkpoint_transfer, checkpoint, checkpoint_file, store]
import ../../../src/lib/atomic_file
import ../../../src/codec/[state_trie, state_layout, bounded]
import ../../support/arc_evidence

const FileName = "state-checkpoint-transfer.bin"
proc policy(): StateStoreLimits =
  ## Present-empty and binary records fit small independently enforced restoration limits.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(200), nodes: TrieNodeLimit(1024)), writes: ElementLimit(4),
        writeValueBytes: ByteLimit(200))
proc detached(): PreparedCheckpoint =
  ## Source store and snapshots disappear before any caller can publish this independent buffer owner.
  var key = default(array[31, byte])
  key[0] = 1
  let store = newStateStore([StateEntry(key: StateKey(key), value: @[0'u8, 255])], policy()).value
  prepareFullCheckpoint(store.snapshot.value, ByteLimit(1000))
proc cycle() =
  ## Prepared success/refusal and explicit move retire their sole buffers before observing ARC occupancy.
  var source = detached()
  var moved = move(source)
  assert moved.error == CheckpointError.None
  assert source.error == CheckpointError.Uninitialized, "moved source tag is disarmed"
  let invalid = prepareFullCheckpoint(default(StateStoreSnapshot), ByteLimit(0))
  assert invalid.error == CheckpointError.Uninitialized
proc main() =
  ## Bytes remain private across exact/short publication and repeated moves; caller root authority is still separate.
  var path = FileName
  defer: discard posix.unlink(path.toCString()) # Test-owned publication leaves no long-lived native resource.
  let absent = default(PreparedCheckpoint)
  assert absent.error == CheckpointError.Uninitialized
  assert absent.publish(FileName, ByteLimit(1000)) == AtomicFileError.Uninitialized
  var prepared = detached()
  assert prepared.error == CheckpointError.None
  let expected = prepared.root
  let extent = prepared.byteLength
  assert prepared.publish(FileName, ByteLimit(uint64(extent - 1))) == AtomicFileError.LimitExceeded
  assert prepared.publish(FileName, ByteLimit(uint64(extent))) == AtomicFileError.None
  let bytes = readBoundedFile(FileName, ByteLimit(1000)).value
  let restored = loadFullCheckpoint(FileName, expected, policy(), ByteLimit(1000)).value
  assert encodeFullCheckpoint(restored.snapshot.value, ByteLimit(1000)).value == bytes
  var moved = move(prepared)
  assert prepared.error == CheckpointError.Uninitialized, "moved prepared tag is disarmed"
  assert moved.error == CheckpointError.None and moved.byteLength == extent
  assert array[32, byte](moved.root) == array[32, byte](expected)
  assert moved.publish(FileName, ByteLimit(1000)) == AtomicFileError.None
  assert readBoundedFile(FileName, ByteLimit(1000)).value == bytes
  assert prepared.publish(FileName, ByteLimit(1000)) == AtomicFileError.Uninitialized
  let empty = newStateStore([], policy()).value.snapshot.value
  let refused = prepareFullCheckpoint(empty, ByteLimit(0))
  assert refused.error == CheckpointError.LimitExceeded
  assert refused.publish(FileName, ByteLimit(1000)) == AtomicFileError.Uninitialized
  assert readBoundedFile(FileName, ByteLimit(1000)).value ==
      bytes # Failed/moved-from sources never replace the published complete map.
  cycle()
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle() # No retired source map, duplicate transfer buffer or failed prefix may remain.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_transfer", 1000, before, after)
  echo "PASS prepared checkpoints: exclusive moved bytes, retired source graphs and exact bounded publication"
main()
