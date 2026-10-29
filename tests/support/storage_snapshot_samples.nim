# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed complete-map selections support snapshot encoding ownership and separate-process peak probes.
import std/assertions
import ../../src/storage/full/state_trie as full_state_trie
import ../../src/storage/node/[repository as node_repository, records as node_records]
import ../../src/storage/[record_codec, snapshot_codec]
import ../../src/codec/bounded
import ../../src/codec/state/[layout as state_layout, trie as state_trie]

type SnapshotFixture* = object ## Only the opaque immutable union and fixed scalar policy survive fixture creation.
  selection*: RepositorySelection
  limits*: SnapshotLimits

proc snapshotPolicy*(): SnapshotLimits =
  ## Explicit fixed ceilings cover the finite fixture panel without input-derived policy relaxation.
  SnapshotLimits(repository: RepositoryLimits(codec: RecordLimits(trie: StateTrieLimits(
    items: ElementLimit(65536), perValue: ByteLimit(256), totalValueBytes: ByteLimit(16777216),
    nodes: TrieNodeLimit(200000)), records: TrieExportLimits(records: TrieNodeLimit(200000),
    valueBytes: ByteLimit(16777216)), encoded: ByteLimit(67108864)),
    records: ElementLimit(200000), valueBytes: ByteLimit(16777216)),
    roots: ElementLimit(64), context: ByteLimit(64), bytes: ByteLimit(67108864))

proc snapshotFixture*(count, size: int): SnapshotFixture =
  ## Build and admit authored complete keys/values; close the mutable owner before exposing the selection.
  assert count > 0 and count <= 65536 and size >= 0 and size <= 256
  let limits = snapshotPolicy()
  var entries = newSeq[StateEntry](count)
  for number in 0..<count:
    var raw = default(array[31, byte])
    raw[0] = byte(number shr 8)
    raw[1] = byte(number and 255)
    var payload = newSeq[byte](size)
    for offset in 0..<size: payload[offset] = byte((number+offset) and 255)
    entries[number] = StateEntry(key: StateKey(raw), value: payload)
  let trie = newFullStateTrie(entries, FullStateTrieLimits(
      trie: limits.repository.codec.trie)).value
  let batch = exportFullTrie(trie, limits.repository.codec.records).value
  let encoded = encodeTrieExport(batch, limits.repository.codec).value
  var owner = newNodeRepository(limits.repository)
  let view = owner.publishEncoded(owner.snapshot.value, encoded).value
  let selected = selectRepositoryRoots(view, [view.commitment.root], limits.roots).value
  assert owner.close == RepositoryError.None
  result = SnapshotFixture(selection: selected, limits: limits)
