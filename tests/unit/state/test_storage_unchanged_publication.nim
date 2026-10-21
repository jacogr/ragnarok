# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Unchanged complete-root publication advances exact revisions while preserving immutable physical bytes.
# @@Verification={"arc": "storage_unchanged_publication_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_samples, arc_evidence]
import ../../../src/storage/[full_state_trie, node_records, node_repository]
import ../../../src/codec/[state_layout, state_trie, bounded]
proc cycle() =
  ## Retained readers survive context-only revisions, stale handles and malformed metadata refusals.
  let limits = storageLimits()
  let trie = storageTrie()
  let full = exportFullTrie(trie, limits.codec.records).value
  var repository = newNodeRepository(limits)
  let first = repository.publish(repository.snapshot.value, full).value
  let unchanged = TrieExport(base: first.commitment.root, root: first.commitment.root,
    entries: uint64(first.commitment.entries), nodes: first.commitment.nodes)
  let next = repository.publish(first, unchanged).value
  assert uint64(first.generation) == 1 and uint64(next.generation) == 2
  assert first.storedNodes == next.storedNodes
  for record in full.records:
    assert first.lookupNode(record.digest).value.payload == next.lookupNode(
        record.digest).value.payload
  assert repository.publish(first, unchanged).error == RepositoryError.StaleView
  var wrong = unchanged
  wrong.entries = 1
  assert repository.publish(next, wrong).error == RepositoryError.InvalidGraph
  wrong = unchanged
  wrong.nodes += 1
  assert repository.publish(next, wrong).error == RepositoryError.InvalidGraph
  wrong = unchanged
  wrong.base = default(StateRoot)
  assert repository.publish(next, wrong).error == RepositoryError.BaseMismatch
  var missing = default(array[32, byte])
  missing[0] = 42
  wrong = unchanged
  wrong.root = StateRoot(missing)
  assert repository.publish(next, wrong).error == RepositoryError.MissingNode
  var foreign = newNodeRepository(limits)
  let other = foreign.publish(foreign.snapshot.value, full).value
  assert repository.publish(other, unchanged).error == RepositoryError.StaleView
  assert foreign.close == RepositoryError.None
  let changedTrie = storageTrie(8)
  let changed = repository.publish(next, exportTrieChanges(trie, changedTrie,
      limits.codec.records).value).value
  assert uint64(changed.generation) == 3 and changed.storedNodes == 5
  let back = TrieExport(base: changed.commitment.root, root: first.commitment.root,
    entries: uint64(first.commitment.entries), nodes: first.commitment.nodes)
  let restored = repository.publish(changed, back).value
  assert uint64(restored.generation) == 4 and restored.storedNodes == 5
  assert restoreStateEntries(restored, first.commitment.root, limits.codec.trie).value[0].value == @[7'u8]
  var copy = next.lookupNode(full.records[0].digest).value
  copy.payload[0] = 99
  assert first.lookupNode(full.records[0].digest).value.payload == @[7'u8]
  assert repository.close == RepositoryError.None
  assert next.lookupNode(full.records[0].digest).value.payload == @[7'u8]
  var empty = newNodeRepository(limits)
  let zero = empty.snapshot.value
  let published = empty.publish(zero, default(TrieExport)).value
  assert uint64(published.generation) == 1 and uint64(zero.generation) == 0
  assert published.storedNodes == 0
  assert empty.publish(zero, default(TrieExport)).error == RepositoryError.StaleView
  assert empty.close == RepositoryError.None
for iteration in 0..<25: cycle() # Warm unchanged, ordinary changed and historical-root selection paths.
let before = getOccupiedMem()
for iteration in 0..<1000: cycle() # Shared tables must retire once after every independent reader releases.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_unchanged_publication", 1000, before, after)
echo "PASS storage unchanged publication: exact revisions, retained bytes, rejection and ARC"
