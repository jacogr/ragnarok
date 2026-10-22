# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded larger synthetic fixtures use distinct four-byte key/value identities without changing runtime policy.
import std/assertions
import ../../src/storage/[node_repository, record_codec, node_records]
import ../../src/codec/[bounded, state_layout, state_trie]

proc deploymentKey*(index: int): StateKey =
  ## Big-endian four-byte identities cross the old two-byte boundary while preserving sorted map order.
  assert index >= 0 and index < 131072
  var raw = default(array[31, byte])
  for position in 0..<4:
    # Every shift is bounded and the nonnegative ordinal fits the admitted key domain.
    raw[position] = byte((index shr ((3-position)*8)) and 255)
  result = StateKey(raw)

proc deploymentValue*(index, revision: int): seq[byte] =
  ## Complete index/revision prefixes prevent artificial payload deduplication or low-byte wrap aliases.
  assert index >= 0 and index < 131072 and revision >= 0 and revision <= 64
  result = newSeq[byte](256)
  for position in 0..<256:
    # Independently predictable trailing bytes make complete-payload corruption observable.
    result[position] = byte((index+position) and 255)
  for position in 0..<4:
    # Revision and index identities occupy disjoint fixed-width byte fields.
    result[position] = byte((revision shr (position*8)) and 255)
    result[position+4] = byte((index shr (position*8)) and 255)

proc deploymentRevision*(index, count, publications: int): int =
  ## Sweep publications touch exactly four advancing keys; all other values retain revision zero.
  assert count in [1024, 32768, 65536, 131072] and publications in [0, 16, 64]
  assert index >= 0 and index < count
  result = if index < publications*4: index div 4+1 else: 0

proc deploymentLimits*(): RepositoryLimits =
  ## Benchmark-only ceilings bound complete graphs, accumulated records, payloads and encoded frames independently.
  let trie = StateTrieLimits(items: ElementLimit(131072), perValue: ByteLimit(256),
    totalValueBytes: ByteLimit(33554432), nodes: TrieNodeLimit(400000))
  result = RepositoryLimits(codec: RecordLimits(trie: trie,
    records: TrieExportLimits(records: TrieNodeLimit(400000), valueBytes: ByteLimit(67108864)),
    encoded: ByteLimit(134217728)), records: ElementLimit(600000), valueBytes: ByteLimit(134217728))
