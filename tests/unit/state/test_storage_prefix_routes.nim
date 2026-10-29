# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored complete two-leaf graphs exercise every full-key route depth and masked byte boundary.
import std/[assertions, syncio]
import ../../support/storage_samples
import ../../../src/storage/node/[records as node_records, repository as node_repository]
import ../../../src/storage/record_codec
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]

proc fixture(depth: int, pattern: byte, wrong = -1): TrieExport =
  ## Build valid local hashes independently of the trie builder, optionally misrouting one edge.
  var leftKey = default(array[31, byte])
  for index in 0..<31:
    leftKey[index] = pattern # Nonzero common prefixes exercise both physical child directions.
  let mask = byte(128 shr (depth mod 8))
  leftKey[depth div 8] = leftKey[depth div 8] and not mask
  var rightKey = leftKey
  rightKey[depth div 8] = rightKey[depth div 8] or mask
  let a = StateKey(leftKey)
  let b = StateKey(rightKey)
  let left = hashStateNode(encodeStateLeaf(a, @[7'u8], storageLimits().codec.trie.perValue).value).value
  let right = hashStateNode(encodeStateLeaf(b, @[], storageLimits().codec.trie.perValue).value).value
  result = TrieExport(entries: 2, nodes: uint64(depth+3), records: @[
    TrieRecord(kind: TrieRecordKind.Leaf, digest: left, key: a, payload: @[7'u8]),
    TrieRecord(kind: TrieRecordKind.Leaf, digest: right, key: b)])
  var child = default(StateNodeHash)
  var bit = depth
  while bit >= 0:
    # Two leaves diverge at depth; outer unary paths carry both descendants and are canonical.
    var first = default(StateNodeHash)
    var second = default(StateNodeHash)
    if bit == depth:
      first = left
      second = right
      if wrong == depth:
        first = right
        second = left # Locally valid hashes cannot authorize reversed complete-key routes.
    else:
      let highBit = (leftKey[bit div 8] and byte(128 shr (bit mod 8))) != 0
      if highBit != (wrong == bit): second = child
      else: first = child # Flip exactly the requested earlier route bit, preserving all local hashes.
    child = hashStateNode(encodeStateBranch(first, second)).value
    result.records.add(TrieRecord(kind: TrieRecordKind.Branch, digest: child,
      left: first, right: second))
    dec bit
  result.root = StateRoot(array[32, byte](child))

for depth in 0..<248:
  # Cover every aligned/partial byte length, including full depth248 and unvisited trailing bits.
  for pattern in [0'u8, 255'u8, 170'u8]:
    let limits = storageLimits()
    var repository = newNodeRepository(limits)
    let empty = repository.snapshot.value
    let batch = fixture(depth, pattern)
    let admitted = repository.publish(empty, batch)
    assert admitted.error == RepositoryError.None
    let view = admitted.value
    let entries = restoreStateEntries(view, view.commitment.root, limits.codec.trie).value
    assert entries.len == 2 and entries[0].value == @[7'u8] and entries[1].value.len == 0
    for wrong in [0, depth div 2, depth]:
      # First, interior and final routed bits must reject atomically even with self-consistent hashes.
      var rejected = newNodeRepository(limits)
      assert validateTrieExport(fixture(depth, pattern, wrong), limits.codec) == RecordError.None
      assert rejected.publish(rejected.snapshot.value, fixture(depth, pattern, wrong)).error ==
        RepositoryError.InvalidGraph
      assert uint64(rejected.snapshot.value.generation) == 0
      assert rejected.close == RepositoryError.None
    assert repository.close == RepositoryError.None
    assert restoreStateEntries(view, view.commitment.root, limits.codec.trie).value.len == 2

echo "PASS storage prefix routes: all248 depths, byte masks, wrong-path rejection and retained maps"
