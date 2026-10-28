# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded multi-root export detaches shared physical records without granting publication authority.
# @@Verification={"arc": "storage_retention_export_arc_release"}
import std/assertions
import std/syncio
import ../../support/storage_samples
import ../../support/testing_arc_evidence
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/bounded as codec_bounded
proc less(left, right: StateNodeHash): bool =
  ## Compare complete addresses independently of repository search/sort helpers.
  let a = array[32, byte](left)
  let b = array[32, byte](right)
  for index in 0..<32:
    if a[index] != b[index]: return a[index] < b[index] # First differing full-address octet fixes order.
  false
proc cycle() =
  ## Export only first/last roots and verify every retained record against independent full transports.
  let limits = storageLimits()
  let first = storageTrie(7)
  let middle = storageTrie(8)
  let last = storageTrie(10)
  var repository = newNodeRepository(limits)
  let a = repository.publish(repository.snapshot.value, exportFullTrie(first,
      limits.codec.records).value).value
  let b = repository.publish(a, exportTrieChanges(first, middle, limits.codec.records).value).value
  let c = repository.publish(b, exportTrieChanges(middle, last, limits.codec.records).value).value
  let plan = selectRepositoryRoots(c, [first.commitment.root, last.commitment.root], ElementLimit(2)).value
  let exact = TrieExportLimits(records: TrieNodeLimit(5), valueBytes: ByteLimit(3))
  var records = exportRepositorySelection(plan, exact).value
  assert records.len == 5 and uint64(plan.generation) == 3
  assert array[32, byte](plan.commitment.root) == array[32, byte](last.commitment.root)
  for index in 1..<records.len:
    assert less(records[index-1].digest, records[index].digest) # No duplicate shared leaf or unstable root-order sorting.
  for trie in [first, last]:
    for expected in exportFullTrie(trie, limits.codec.records).value.records:
      var found = false
      for record in records:
        if array[32, byte](record.digest) == array[32, byte](expected.digest):
          assert record.kind == expected.kind and record.payload == expected.payload
          assert array[31, byte](record.key) == array[31, byte](expected.key)
          assert array[32, byte](record.left) == array[32, byte](expected.left)
          assert array[32, byte](record.right) == array[32, byte](expected.right)
          found = true
      assert found # Independent full exports witness all roots in the retained union.
  let reversed = selectRepositoryRoots(c, [last.commitment.root, first.commitment.root],
      ElementLimit(2)).value
  let reordered = exportRepositorySelection(reversed, exact).value
  for index in 0..<records.len:
    assert array[32, byte](records[index].digest) == array[32, byte](reordered[index].digest)
  for index in 0..<records.len:
    if records[index].payload.len > 0: records[index].payload[
        0] = 99 # Output mutation cannot alter source or another export.
  let fresh = exportRepositorySelection(plan, exact).value
  for record in fresh:
    if record.payload.len > 0: assert record.payload[0] != 99
  assert exportRepositorySelection(plan, TrieExportLimits(records: TrieNodeLimit(4),
      valueBytes: ByteLimit(3))).error == RepositoryError.LimitExceeded
  assert exportRepositorySelection(plan, TrieExportLimits(records: TrieNodeLimit(5),
      valueBytes: ByteLimit(2))).error == RepositoryError.LimitExceeded
  assert exportRepositorySelection(default(RepositorySelection), exact).error ==
      RepositoryError.Uninitialized
  assert repository.close == RepositoryError.None
  assert exportRepositorySelection(plan, exact).value.len ==
      5 # Source ownership survives file/memory handle retirement.
  var empty = newNodeRepository(limits)
  let zero = selectRepositoryRoots(empty.snapshot.value, [default(StateRoot)], ElementLimit(1)).value
  assert exportRepositorySelection(zero, default(TrieExportLimits)).value.len == 0
  assert empty.close == RepositoryError.None
for iteration in 0..<25: cycle() # Warm detached buffers and exact/short budget branches.
let before = getOccupiedMem()
for iteration in 0..<1000: cycle() # All plans, sorted indices and detached transports retire acyclically.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_retention_export", 1000, before, after)
echo "PASS storage retention export: complete unions, sorted detached records, exact budgets and ARC"
