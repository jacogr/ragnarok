# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Multi-root image admission preserves generations and rejects partial, orphaned or noncanonical unions.
# @@Verification={"arc": "storage_image_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_samples, arc_evidence]
import ../../../src/storage/[full_state_trie, node_records, node_repository]
import ../../../src/codec/[state_layout, state_trie, bounded]
proc cycle() =
  ## Export selected first/last roots, admit their exact union and continue ordinary delta publication.
  var limits = storageLimits()
  limits.codec.trie.totalValueBytes = ByteLimit(2)
  let a = storageTrie(7)
  let b = storageTrie(8)
  let c = storageTrie(10)
  var source = newNodeRepository(limits)
  let first = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.codec.records).value).value
  let second = source.publish(first, exportTrieChanges(a, b, limits.codec.records).value).value
  let third = source.publish(second, exportTrieChanges(b, c, limits.codec.records).value).value
  let selected = selectRepositoryRoots(third, [a.commitment.root, c.commitment.root], ElementLimit(2)).value
  let image = exportRepositoryImage(selected, TrieExportLimits(records: TrieNodeLimit(5),
      valueBytes: ByteLimit(3)), ElementLimit(2)).value
  var restored = restoreRepositoryImage(image, limits, ElementLimit(2), ByteLimit(1000000)).value
  let view = restored.snapshot.value
  assert uint64(view.generation) == 3 and view.storedNodes == 5
  for root in image.roots:
    assert restoreHistoricalStateEntries(view, root, limits.codec.trie).value.len ==
        2 # Both complete maps survive; the unselected middle map does not.
  assert restoreHistoricalStateEntries(view, b.commitment.root, limits.codec.trie).error ==
      RepositoryError.MissingNode
  let changed = storageTrie(12)
  assert uint64(restored.publish(view, exportTrieChanges(c, changed,
      limits.codec.records).value).value.generation) == 4
  var bad = image
  bad.generation = RepositoryGeneration(0)
  assert restoreRepositoryImage(bad, limits, ElementLimit(2), ByteLimit(1000000)).error ==
      RepositoryError.InvalidGraph
  bad = image
  bad.commitment.entries = 1
  assert restoreRepositoryImage(bad, limits, ElementLimit(2), ByteLimit(1000000)).error ==
      RepositoryError.InvalidGraph
  bad = image
  let duplicateRoot = bad.roots[1]
  bad.roots[0] = duplicateRoot
  assert restoreRepositoryImage(bad, limits, ElementLimit(2), ByteLimit(1000000)).error ==
      RepositoryError.InvalidGraph
  bad = image
  bad.collection.records[0].digest = default(StateNodeHash)
  assert restoreRepositoryImage(bad, limits, ElementLimit(2), ByteLimit(1000000)).error ==
      RepositoryError.InvalidRecords
  assert restoreRepositoryImage(image, limits, ElementLimit(1), ByteLimit(1000000)).error ==
      RepositoryError.LimitExceeded
  let complete = selectRepositoryRoots(third, [a.commitment.root, b.commitment.root,
      c.commitment.root], ElementLimit(3)).value
  var orphan = exportRepositoryImage(complete, limits.codec.records, ElementLimit(3)).value
  orphan.roots = image.roots
  assert restoreRepositoryImage(orphan, limits, ElementLimit(3), ByteLimit(1000000)).error ==
      RepositoryError.InvalidGraph
  bad = image
  let fewerRecords = bad.collection.records[0..<bad.collection.records.len-1]
  bad.collection.records = fewerRecords
  assert restoreRepositoryImage(bad, limits, ElementLimit(2), ByteLimit(1000000)).error !=
      RepositoryError.None
  bad = image
  var isolated = restoreRepositoryImage(bad, limits, ElementLimit(2), ByteLimit(1000000)).value
  for index in 0..<bad.collection.records.len:
    if bad.collection.records[index].kind == TrieRecordKind.Leaf:
      bad.collection.records[index].payload[0] = 99 # Admitted owners must not borrow caller-owned leaf bytes.
  assert restoreStateEntries(isolated.snapshot.value, c.commitment.root, limits.codec.trie).value[
      0].value == @[10'u8]
  assert isolated.close == RepositoryError.None
  assert source.close == RepositoryError.None and restored.close == RepositoryError.None
  assert third.storedNodes == 7 and selected.retainedNodes == 5
proc emptyCurrent() =
  ## A currently empty map may retain nonempty historical roots without fake target metadata.
  let limits = storageLimits()
  let trie = storageTrie()
  var source = newNodeRepository(limits)
  let first = source.publish(source.snapshot.value, exportFullTrie(trie,
      limits.codec.records).value).value
  let empty = source.publish(first, TrieExport(base: first.commitment.root)).value
  let selected = selectRepositoryRoots(empty, [default(StateRoot), first.commitment.root],
      ElementLimit(2)).value
  let image = exportRepositoryImage(selected, limits.codec.records, ElementLimit(2)).value
  var restored = restoreRepositoryImage(image, limits, ElementLimit(2), ByteLimit(1000000)).value
  assert restored.snapshot.value.commitment.entries == 0 and restored.snapshot.value.storedNodes == 3
  assert restoreHistoricalStateEntries(restored.snapshot.value, first.commitment.root,
      limits.codec.trie).value.len == 2
  assert source.close == RepositoryError.None and restored.close == RepositoryError.None
for iteration in 0..<25: cycle() # Warm all complete-root and malformed-image branches.
let before = getOccupiedMem()
for iteration in 0..<1000: cycle() # Raw transport, admitted tables and retained sources retire independently.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_image", 1000, before, after)
emptyCurrent()
echo "PASS storage image: complete root unions, exact generations, admission, empty current and ARC"
