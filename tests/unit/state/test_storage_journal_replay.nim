# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict fused journal replay preserves checksum, generation, graph and detached context boundaries.
# @@Verification={"arc": "storage_journal_replay_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_samples, arc_evidence]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/records as node_records
import ../../../src/storage/record_codec
import ../../../src/storage/node/repository as node_repository
import ../../../src/storage/journal_codec
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset genuine cryptographic attempt counters.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count outer frame integrity separately from inner physical hashes.
proc cycle() =
  ## Both schemas enforce contiguous generation and own successful revision/context bytes independently.
  let limits = storageLimits()
  let a = storageTrie(7)
  let b = storageTrie(8)
  let full = exportFullTrie(a, limits.codec.records).value
  let delta = exportTrieChanges(a, b, limits.codec.records).value
  let wire = encodeJournalFrame(RepositoryGeneration(1), full, limits.codec, ByteLimit(1000000)).value
  var contextWire = encodeContextJournalFrame(RepositoryGeneration(2), delta, [9'u8, 8],
    ByteLimit(2), limits.codec, ByteLimit(1000000)).value
  var owner = newNodeRepository(limits)
  let empty = owner.snapshot.value
  reset(0)
  let first = owner.replayJournalFrame(empty, wire, ByteLimit(1000000)).value
  assert int(calls()) == full.records.len+1 and first.context.len == 0
  reset(0)
  let next = owner.replayContextJournalFrame(first.view, contextWire, ByteLimit(2), ByteLimit(1000000)).value
  assert int(calls()) == delta.records.len+1 and next.context == @[9'u8, 8]
  assert uint64(next.view.generation) == 2
  assert owner.replayJournalFrame(next.view, wire, ByteLimit(1000000)).error ==
      FrameError.InvalidRevision
  for stop in 0..<contextWire.len:
    # Even a complete prefix of a contextual frame must not become a partial next revision.
    assert owner.replayContextJournalFrame(next.view, contextWire.toOpenArray(0, stop-1),
      ByteLimit(2), ByteLimit(1000000)).error != FrameError.None
    assert uint64(owner.snapshot.value.generation) == 2
  var corrupt = wire
  corrupt[20] = corrupt[20] xor 1
  assert owner.replayJournalFrame(next.view, corrupt, ByteLimit(1000000)).error ==
      FrameError.ChecksumMismatch
  var blank = newNodeRepository(limits)
  let wrongGeneration = encodeJournalFrame(RepositoryGeneration(2), full, limits.codec, ByteLimit(1000000)).value
  assert blank.replayJournalFrame(blank.snapshot.value, wrongGeneration, ByteLimit(
      1000000)).error == FrameError.InvalidRevision
  var wrong = full
  wrong.entries = 1
  let bad = encodeJournalFrame(RepositoryGeneration(1), wrong, limits.codec, ByteLimit(1000000)).value
  assert blank.replayJournalFrame(blank.snapshot.value, bad, ByteLimit(1000000)).error ==
      FrameError.InvalidRevision
  assert uint64(blank.snapshot.value.generation) == 0
  var narrow = newNodeRepository(limits)
  let noContext = encodeContextJournalFrame(RepositoryGeneration(1), full, [1'u8, 2],
    ByteLimit(2), limits.codec, ByteLimit(1000000)).value
  assert narrow.replayContextJournalFrame(narrow.snapshot.value, noContext, ByteLimit(1), ByteLimit(
      1000000)).error == FrameError.LimitExceeded
  assert narrow.replayJournalFrame(narrow.snapshot.value, wire, ByteLimit(wire.len-1)).error ==
      FrameError.LimitExceeded
  var shortPolicy = limits
  shortPolicy.codec.encoded = ByteLimit(1)
  var short = newNodeRepository(shortPolicy)
  reset(0)
  assert short.replayJournalFrame(short.snapshot.value, wire, ByteLimit(1000000)).error ==
      FrameError.LimitExceeded
  assert int(calls()) == 0 # The inner byte ceiling must refuse before outer checksum hashing.
  assert short.close == RepositoryError.None
  for index in 0..<contextWire.len:
    contextWire[index] = 0 # Successful context and record ownership must survive caller mutation.
  assert next.context == @[9'u8, 8]
  assert owner.close == RepositoryError.None and blank.close == RepositoryError.None
  assert narrow.close == RepositoryError.None
  assert restoreStateEntries(first.view, a.commitment.root, limits.codec.trie).value[0].value == @[7'u8]
  assert restoreStateEntries(next.view, b.commitment.root, limits.codec.trie).value[0].value == @[8'u8]
for iteration in 0..<10:
  cycle() # Warm all admitted, corrupt and quota-refused replay paths.
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle() # Replay transports, context and immutable roots retire acyclically.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_journal_replay", 1000, before, after)
echo "PASS storage journal replay: single hashing, exact frames, contiguous generations, context and ARC"
