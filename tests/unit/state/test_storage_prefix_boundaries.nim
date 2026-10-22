# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Same-prefix addresses cannot bypass full equality, canonical image order, graph uniqueness or limits.
import std/[assertions, syncio]
import ../../support/storage_growth_samples
import ../../../src/storage/[node_repository, node_records, full_state_trie, record_codec]
import ../../../src/codec/[state_layout, state_trie, bounded]

proc prefix(digest: StateNodeHash): int =
  ## Independent witness selection shares twelve bits without treating the prefix as an address.
  let raw = array[32, byte](digest)
  (int(raw[0]) shl 4) or (int(raw[1]) shr 4)
let limits = growthLimits()
let fixture = prepareGrowth(8192, 64)
var owner = newNodeRepository(limits)
let view = owner.publish(owner.snapshot.value, fixture.seed).value
let selection = selectRepositoryRoots(view, [view.commitment.root], ElementLimit(1)).value
let image = exportRepositoryImage(selection, limits.codec.records, ElementLimit(1)).value
var pair = -1
for index in 1..<image.collection.records.len:
  # More physical records than twelve-bit intervals guarantees an occupied interval with distinct neighbors.
  if prefix(image.collection.records[index-1].digest) == prefix(image.collection.records[index].digest):
    pair = index
    break
assert pair > 0
let first = image.collection.records[pair-1]
let second = image.collection.records[pair]
assert array[32, byte](first.digest) != array[32, byte](second.digest)
assert array[32, byte](view.lookupNode(first.digest).value.digest) == array[32, byte](first.digest)
assert array[32, byte](view.lookupNode(second.digest).value.digest) == array[32, byte](second.digest)
var reversed = image
reversed.collection.records[pair-1] = second
reversed.collection.records[pair] = first
assert restoreRepositoryImage(reversed, limits, ElementLimit(1), limits.codec.encoded).error ==
    RepositoryError.InvalidGraph
var narrow = limits
narrow.codec.trie.nodes = TrieNodeLimit(image.commitment.nodes-1)
assert restoreRepositoryImage(image, narrow, ElementLimit(1), limits.codec.encoded).error ==
    RepositoryError.LimitExceeded
var leaf = default(TrieRecord)
var found = false
for record in fixture.seed.records:
  # A genuine committed leaf provides independently valid hash/payload material for malformed graph edges.
  if record.kind == TrieRecordKind.Leaf:
    leaf = record
    found = true
    break
assert found
var duplicate = TrieRecord(kind: TrieRecordKind.Branch, left: leaf.digest, right: leaf.digest)
duplicate.digest = hashStateNode(encodeStateBranch(duplicate.left, duplicate.right)).value
let duplicateBatch = TrieExport(root: StateRoot(array[32, byte](duplicate.digest)), entries: 2,
  nodes: 3, records: @[leaf, duplicate])
var rejected = newNodeRepository(limits)
let empty = rejected.snapshot.value
assert rejected.publish(empty, duplicateBatch).error == RepositoryError.InvalidGraph
assert uint64(rejected.snapshot.value.generation) == 0
var raw = default(array[32, byte])
let address = array[32, byte](leaf.digest)
raw[0] = address[0]
raw[1] = address[1] and 240
raw[31] = 1
assert raw != address
let missing = StateNodeHash(raw)
var incomplete = TrieRecord(kind: TrieRecordKind.Branch, left: leaf.digest, right: missing)
incomplete.digest = hashStateNode(encodeStateBranch(incomplete.left, incomplete.right)).value
assert array[32, byte](incomplete.digest) != raw
let incompleteBatch = TrieExport(root: StateRoot(array[32, byte](incomplete.digest)), entries: 2,
  nodes: 3, records: @[leaf, incomplete])
# A missing full address sharing the existing leaf's prefix must stay MissingNode, not alias that leaf.
assert rejected.publish(empty, incompleteBatch).error == RepositoryError.MissingNode
assert uint64(rejected.snapshot.value.generation) == 0
assert rejected.close == RepositoryError.None
assert owner.close == RepositoryError.None
checkGrowthHead(view, fixture.roots[0], 8192, 0)
echo "PASS storage prefix boundaries"
