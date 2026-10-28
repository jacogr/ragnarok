# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_publish_arc_release"}

## Real sibling-file replacement and directory synchronization preserve complete checkpoint publication.

import std/assertions
import std/syncio
import std/posix/posix
import ../../../src/state/checkpoint_file as state_checkpoint_file
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/store as state_store
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/bounded as codec_bounded
import ../../support/testing_arc_evidence

const FileName = "state-checkpoint-publish.bin"
proc policy(): StateStoreLimits =
  ## Small complete maps make repeated durable publications bounded without protocol fixtures.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(1), perValue: ByteLimit(1),
    totalValueBytes: ByteLimit(1), nodes: TrieNodeLimit(1024)),
    writes: ElementLimit(1), writeValueBytes: ByteLimit(1))
proc cycle(snapshot: StateStoreSnapshot) =
  ## Both a complete synchronized replacement and a preflight refusal retire their temporary owners.
  let saved = saveFullCheckpoint(FileName, snapshot, ByteLimit(1000))
  assert saved.error == CheckpointFileError.None
  assert sameStateSnapshot(saved.value, snapshot)
  assert saveFullCheckpoint(FileName, snapshot, ByteLimit(0)).checkpointError ==
      CheckpointError.LimitExceeded
proc main() {.raises.} =
  ## Publish real full snapshots and observe failures without weakening the OS synchronization path.
  var path = FileName
  defer: discard posix.unlink(path.toCString()) # The runner owns this isolated generated destination.
  var directory = "state-checkpoint-publish-target"
  discard posix.rmdir(directory.toCString()) # Retire only an empty runner-owned directory from an interrupted earlier run.
  assert posix.mkdir(directory.toCString(), Mode(0o700)) == 0
  defer: discard posix.rmdir(directory.toCString()) # A real directory forces rename refusal after temporary file synchronization.
  let empty = newStateStore([], policy()).value.snapshot.value
  let first = saveFullCheckpoint(FileName, empty, ByteLimit(1000))
  assert first.error == CheckpointFileError.None
  assert sameStateSnapshot(first.value, empty)
  assert encodeFullCheckpoint(loadFullCheckpoint(FileName, policy(), ByteLimit(
      1000)).value.snapshot.value,
    ByteLimit(1000)).value == encodeFullCheckpoint(empty, ByteLimit(1000)).value
  let next = newStateStore([StateEntry(key: default(StateKey), value: @[42'u8])], policy()).value.snapshot.value
  assert saveFullCheckpoint(FileName, next, ByteLimit(1000)).error == CheckpointFileError.None
  let retained = loadFullCheckpoint(FileName, policy(), ByteLimit(1000)).value.snapshot.value
  assert retained.lookup(default(StateKey)).value.bytes == @[42'u8]
  let beforeFile = readFile(FileName)
  assert saveFullCheckpoint(FileName, next, ByteLimit(0)).error ==
      CheckpointFileError.InvalidCheckpoint
  assert saveFullCheckpoint(FileName, default(StateStoreSnapshot), ByteLimit(
      1000)).checkpointError == CheckpointError.Uninitialized
  assert readFile(FileName) == beforeFile # Preflight refusals cannot replace or truncate existing bytes.
  assert saveFullCheckpoint("", next, ByteLimit(1000)).error == CheckpointFileError.InvalidPath
  var invalidPath = "xyz"
  invalidPath[1] = char(0)
  assert saveFullCheckpoint(invalidPath, next, ByteLimit(1000)).error ==
      CheckpointFileError.InvalidPath
  assert saveFullCheckpoint("missing-directory/checkpoint", next, ByteLimit(1000)).error ==
      CheckpointFileError.IoFailure
  assert saveFullCheckpoint(directory, next, ByteLimit(1000)).error == CheckpointFileError.IoFailure
  assert readFile(FileName) == beforeFile # A refused independent publication leaves the existing checkpoint intact.
  assert saveFullCheckpoint(FileName, empty, ByteLimit(1000)).error == CheckpointFileError.None
  assert retained.lookup(default(StateKey)).value.bytes == @[
      42'u8] # Published replacements cannot alter prior restored owners.
  cycle(next)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(next) # Each success executes real file sync, atomic rename and parent-directory sync.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_publish", 1000, before, after)
  echo "PASS checkpoint publication: synced sibling replacement, refusals and exact snapshot ownership"
try:
  main() # An OS exception cannot substitute for the required success transcript.
except:
  quit(2)
