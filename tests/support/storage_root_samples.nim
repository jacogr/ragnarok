# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent singleton historical maps form large complete root unions without quadratic publication setup.
import std/[algorithm, assertions]
import ../../src/storage/node/records as node_records
import ../../src/storage/record_codec
import ../../src/storage/node/repository as node_repository
import ../../src/codec/state/[trie as state_trie, layout as state_layout]
import ../../src/codec/bounded

type RootFixture* = object ## Only an immutable closed-owner view and copied scalar root identities survive setup.
  view*: RepositoryView
  roots*: seq[StateRoot]
  limits*: RepositoryLimits

proc compareRecord(left, right: TrieRecord): int =
  ## Fixture physical order is computed from complete addresses, independent of selection implementation.
  let a = array[32, byte](left.digest)
  let b = array[32, byte](right.digest)
  for index in 0..<32:
    if a[index] < b[index]: return -1 # The first differing octet determines canonical order.
    if a[index] > b[index]: return 1
  0

proc rootFixture*(count: int): RootFixture =
  ## Every nonempty root is one distinct leaf; the zero root represents an independently empty map.
  assert count > 0 and count <= 8192
  let limits = RepositoryLimits(codec: RecordLimits(trie: StateTrieLimits(items: ElementLimit(1),
    perValue: ByteLimit(2), totalValueBytes: ByteLimit(2), nodes: TrieNodeLimit(1)),
    records: TrieExportLimits(records: TrieNodeLimit(8192), valueBytes: ByteLimit(16384)),
    encoded: ByteLimit(1048576)), records: ElementLimit(8192), valueBytes: ByteLimit(16384))
  var records = newSeq[TrieRecord](count)
  for ordinal in 0..<count:
    let payload = @[byte(ordinal shr 8), byte(ordinal and 255)]
    let encoded = encodeStateLeaf(default(StateKey), payload, ByteLimit(2)).value
    let digest = hashStateNode(encoded).value
    assert array[32, byte](digest) != default(array[32, byte])
    records[ordinal] = TrieRecord(kind: TrieRecordKind.Leaf, digest: digest, payload: payload)
  records.sort(compareRecord)
  var roots = newSeq[StateRoot](count+1)
  roots[0] = default(StateRoot)
  for index, record in records:
    roots[index+1] = StateRoot(array[32, byte](record.digest)) # Physical and root identities coincide for singletons.
  let commitment = StateTrieCommitment(root: roots[count], entries: 1, nodes: 1)
  let image = RepositoryImage(generation: RepositoryGeneration(1), commitment: commitment,
    roots: roots, collection: RecordCollection(records: records))
  var owner = restoreRepositoryImage(image, limits, ElementLimit(8193), ByteLimit(1048576)).value
  let view = owner.snapshot.value
  assert owner.close == RepositoryError.None
  result = RootFixture(view: view, roots: roots, limits: limits)
