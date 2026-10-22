# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded larger synthetic fixtures use distinct four-byte key/value identities without changing runtime policy.
import std/assertions
import ../../src/storage/[node_repository, record_codec, node_records, full_state_trie]
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

type DeploymentFixture* = object
  ## Test-owned Merklized transport objects grant no protocol-state or checkpoint authority.
  seed*: TrieExport
  changes*: seq[TrieExport]
  roots*: seq[StateRoot]

proc prepareDeployment*(count, publications: int): DeploymentFixture =
  ## Prepare bounded distinct-value maps and exact physical deltas outside resource-owner observations.
  assert count in [1024, 32768, 65536, 131072] and publications in [16, 64]
  result = default(DeploymentFixture)
  let limits = deploymentLimits()
  var entries: seq[StateEntry] = @[]
  for index in 0..<count:
    # Every initial key has its full independent index payload.
    entries.add(StateEntry(key: deploymentKey(index), value: deploymentValue(index, 0)))
  var state = newFullStateTrie(entries, FullStateTrieLimits(trie: limits.codec.trie,
    writes: ElementLimit(4), writeValueBytes: ByteLimit(1024))).value
  result.seed = exportFullTrie(state, limits.codec.records).value
  result.roots.add(result.seed.root)
  for revision in 1..publications:
    # Bounded advancing writes never wrap within any admitted fixture extent.
    var writes: seq[TrieWrite] = @[]
    for offset in 0..<4:
      let index = (revision-1)*4+offset
      writes.add(TrieWrite(key: deploymentKey(index), kind: TrieWriteKind.Put,
        value: deploymentValue(index, revision)))
    let next = state.apply(writes).value
    result.changes.add(exportTrieChanges(state, next, limits.codec.records).value)
    result.roots.add(next.commitment.root)
    state = next

proc checkDeployment*(view: RepositoryView, root: StateRoot, count, publications: int) =
  ## Closed-form expected payloads validate every sorted key independently of delta preparation.
  let entries = restoreHistoricalStateEntries(view, root, deploymentLimits().codec.trie).value
  assert entries.len == count
  for index, entry in entries:
    # Full four-byte keys and full256-byte payloads must match, including untouched suffix entries.
    assert array[31, byte](entry.key) == array[31, byte](deploymentKey(index))
    assert entry.value == deploymentValue(index, deploymentRevision(index, count, publications))

proc checkDeploymentHead*(view: RepositoryView, root: StateRoot, count, publications: int) =
  ## Full-map reachability cannot substitute for exact selected root and local revision identity.
  assert array[32, byte](view.commitment.root) == array[32, byte](root)
  assert uint64(view.generation) == uint64(publications+1)
  checkDeployment(view, root, count, publications)
