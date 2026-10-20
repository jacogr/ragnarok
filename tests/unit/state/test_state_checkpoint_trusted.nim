# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_trusted_arc_release"}

## An independently trusted complete root distinguishes internally valid but unauthorized checkpoint state.

import std/[assertions, syncio]
import std/posix/posix
import ../../../src/state/[checkpoint, checkpoint_file, store]
import ../../../src/codec/[state_trie, state_layout, bounded]
import ../../support/arc_evidence

proc policy(): StateStoreLimits =
  ## Exact small limits apply equally to trusted and internally valid alternate maps.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(1), perValue: ByteLimit(1),
    totalValueBytes: ByteLimit(1), nodes: TrieNodeLimit(1024)),
    writes: ElementLimit(1), writeValueBytes: ByteLimit(1))
proc cycle(bytes: seq[byte], accepted, refused: StateRoot) =
  ## Both successful and rejected complete candidates retire before allocator observation.
  assert decodeFullCheckpoint(bytes, accepted, policy(), ByteLimit(1000)).error ==
      CheckpointError.None
  assert decodeFullCheckpoint(bytes, refused, policy(), ByteLimit(1000)).error ==
      CheckpointError.RootMismatch
proc main() =
  ## A canonical valid checkpoint cannot choose its own trust anchor, while equal trusted roots restore normally.
  let first = newStateStore([StateEntry(key: default(StateKey), value: @[41'u8])], policy()).value.snapshot.value
  let second = newStateStore([StateEntry(key: default(StateKey), value: @[42'u8])], policy()).value.snapshot.value
  let trusted = first.commitment.root
  let alternate = second.commitment.root
  let bytes = encodeFullCheckpoint(first, ByteLimit(1000)).value
  let otherBytes = encodeFullCheckpoint(second, ByteLimit(1000)).value
  assert decodeFullCheckpoint(otherBytes, policy(), ByteLimit(1000)).error == CheckpointError.None
  let accepted = decodeFullCheckpoint(bytes, trusted, policy(), ByteLimit(1000))
  assert accepted.error == CheckpointError.None
  assert accepted.value.snapshot.value.lookup(default(StateKey)).value.bytes == @[41'u8]
  assert decodeFullCheckpoint(otherBytes, trusted, policy(), ByteLimit(1000)).error ==
      CheckpointError.RootMismatch
  assert decodeFullCheckpoint(bytes, alternate, policy(), ByteLimit(1000)).error ==
      CheckpointError.RootMismatch
  assert decodeFullCheckpoint([], trusted, policy(), ByteLimit(1000)).error ==
      CheckpointError.InvalidFormat
  assert decodeFullCheckpoint(bytes, trusted, policy(), ByteLimit(0)).error ==
      CheckpointError.LimitExceeded
  var path = "state-checkpoint-trusted.bin"
  defer: discard posix.unlink(path.toCString()) # Generated file ownership remains inside the isolated native work directory.
  assert saveFullCheckpoint(path, first, ByteLimit(1000)).error == CheckpointFileError.None
  let loaded = loadFullCheckpoint(path, trusted, policy(), ByteLimit(1000))
  assert loaded.error == CheckpointFileError.None
  assert saveFullCheckpoint(path, second, ByteLimit(1000)).error == CheckpointFileError.None
  let refused = loadFullCheckpoint(path, trusted, policy(), ByteLimit(1000))
  assert refused.error == CheckpointFileError.InvalidCheckpoint
  assert refused.checkpointError == CheckpointError.RootMismatch
  assert loadFullCheckpoint(path, alternate, policy(), ByteLimit(1000)).error ==
      CheckpointFileError.None
  assert loaded.value.snapshot.value.lookup(default(StateKey)).value.bytes == @[41'u8]
  assert first.lookup(default(StateKey)).value.bytes == @[41'u8]
  assert loadFullCheckpoint("missing-trusted-checkpoint", trusted, policy(), ByteLimit(
      1000)).error == CheckpointFileError.IoFailure
  let empty = newStateStore([], policy()).value.snapshot.value
  assert decodeFullCheckpoint(encodeFullCheckpoint(empty, ByteLimit(1000)).value,
    empty.commitment.root, policy(), ByteLimit(1000)).error == CheckpointError.None
  cycle(bytes, trusted, alternate)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(bytes, trusted, alternate) # Root mismatch cannot retain a complete unauthorized map or returned bytes.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_trusted", 1000, before, after)
  echo "PASS trusted checkpoints: independent complete-root authority and exact refusal preservation"
main()
