# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete graph admission and atomic publication preserve all historical immutable physical reads.
# @@Verification={"arc": "storage_repository_arc_release"}
import std/assertions
import std/syncio
import ../../support/storage_samples
import ../../support/testing_arc_evidence
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/record_codec as storage_record_codec
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/bounded as codec_bounded

proc cycle() =
  ## Publish detached changes, retain prior views, reject stale/partial/invalid physical graphs.
  let limits = storageLimits()
  let initial = storageTrie()
  var batch = exportFullTrie(initial, limits.codec.records).value
  var repository = newNodeRepository(limits)
  let empty = repository.snapshot.value
  let first = repository.publish(empty, batch).value
  let leaf = batch.records[0].digest
  let held = first.lookupNode(leaf).value
  assert first.commitment.entries == 2 and first.storedNodes == 3
  assert uint64(first.generation) == 1
  batch.records[0].payload[0] = 99
  assert first.lookupNode(leaf).value.payload == @[7'u8]
  let changed = initial.apply([TrieWrite(key: storageKey(0), kind: TrieWriteKind.Put,
    value: @[8'u8])]).value
  let delta = exportTrieChanges(initial, changed, limits.codec.records).value
  let next = repository.publish(first, delta).value
  assert uint64(next.generation) == 2 and next.storedNodes == 5
  assert held.payload == @[7'u8] and first.lookupNode(leaf).value.payload == @[7'u8]
  assert repository.publish(first, delta).error == RepositoryError.StaleView
  assert repository.publish(next, exportFullTrie(initial, limits.codec.records).value).error ==
      RepositoryError.BaseMismatch
  assert empty.lookupNode(leaf).error == RepositoryError.MissingNode
  # Locally valid branches cannot authorize unavailable child records.
  var independent = newNodeRepository(limits)
  let before = independent.snapshot.value
  var missing = exportFullTrie(initial, limits.codec.records).value
  missing.records = @[missing.records[2]]
  assert independent.publish(before, missing).error == RepositoryError.MissingNode
  # A self-consistent local hash with reversed physical edges fails full key routing.
  var reversed = exportFullTrie(initial, limits.codec.records).value
  let left = reversed.records[2].left
  reversed.records[2].left = reversed.records[2].right
  reversed.records[2].right = left
  reversed.records[2].digest = hashStateNode(encodeStateBranch(reversed.records[2].left,
    reversed.records[2].right)).value
  reversed.root = StateRoot(array[32, byte](reversed.records[2].digest))
  assert independent.publish(before, reversed).error == RepositoryError.InvalidGraph
  var wrong = exportFullTrie(initial, limits.codec.records).value
  wrong.entries = 1
  assert independent.publish(before, wrong).error == RepositoryError.InvalidGraph
  # Single-leaf branches have valid local hashes but violate canonical complete-map topology.
  let full = exportFullTrie(initial, limits.codec.records).value
  let singleBranch = TrieRecord(kind: TrieRecordKind.Branch,
    left: full.records[0].digest, digest: hashStateNode(encodeStateBranch(
      full.records[0].digest, default(StateNodeHash))).value)
  let unary = TrieExport(root: StateRoot(array[32, byte](singleBranch.digest)), entries: 1,
    nodes: 2, records: @[full.records[0], singleBranch])
  assert independent.publish(before, unary).error == RepositoryError.InvalidGraph
  let extra = newFullStateTrie([StateEntry(key: storageKey(64))],
    FullStateTrieLimits(trie: limits.codec.trie)).value
  var orphan = full
  orphan.records.add(exportFullTrie(extra, limits.codec.records).value.records[0])
  assert independent.publish(before, orphan).error == RepositoryError.InvalidGraph
  assert independent.snapshot.value.storedNodes == 0
  # JAM masks the left high bit; physical records must still reject a conflicting full edge.
  var conflict = delta.records[delta.records.len-1]
  var rawLeft = array[32, byte](conflict.left)
  rawLeft[0] = rawLeft[0] xor 128
  conflict.left = StateNodeHash(rawLeft)
  let conflicting = TrieExport(base: next.commitment.root, root: next.commitment.root,
    entries: 2, nodes: 3, records: @[conflict])
  assert validateTrieExport(conflicting, limits.codec) == RecordError.None
  assert repository.publish(next, conflicting).error == RepositoryError.RecordConflict
  assert uint64(repository.snapshot.value.generation) == 2
  var read = first.lookupNode(leaf).value
  read.payload[0] = 88
  assert first.lookupNode(leaf).value.payload == @[7'u8]
  var short = limits
  short.records = ElementLimit(2)
  var bounded = newNodeRepository(short)
  assert bounded.publish(bounded.snapshot.value, exportFullTrie(initial,
      limits.codec.records).value).error == RepositoryError.LimitExceeded
  assert bounded.snapshot.value.storedNodes == 0
  assert repository.close == RepositoryError.None
  assert repository.snapshot.error == RepositoryError.Uninitialized
  assert next.lookupNode(leaf).value.payload == @[
      7'u8] # Closed owners do not retire independently held read views.
  assert independent.close == RepositoryError.None and bounded.close == RepositoryError.None

for i in 0..<25: cycle() # Warm exact input, successful maps and refusal paths.
let before = getOccupiedMem()
for i in 0..<1000: cycle() # All node tables, copied records and retained views retire acyclically.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_repository", 1000, before, after)
echo "PASS storage repository: complete graphs, atomic batches, stale/partial refusal, views and ARC"
