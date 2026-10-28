# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored standalone storage fixtures share finite policies without application/state consumers.
import ../../src/storage/full_state_trie as storage_full_state_trie
import ../../src/storage/node_records as storage_node_records
import ../../src/storage/record_codec as storage_record_codec
import ../../src/storage/node_repository as storage_node_repository
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/bounded as codec_bounded

proc storageKey*(number: byte): StateKey =
  ## Choose independent root branches while retaining every serialized key byte.
  var raw = default(array[31, byte])
  raw[0] = number
  StateKey(raw)
proc storageLimits*(): RepositoryLimits =
  ## Bound complete graphs, transaction bytes and accumulated physical history independently.
  RepositoryLimits(codec: RecordLimits(trie: StateTrieLimits(items: ElementLimit(16),
    perValue: ByteLimit(64), totalValueBytes: ByteLimit(1024), nodes: TrieNodeLimit(4000)),
    records: TrieExportLimits(records: TrieNodeLimit(4000), valueBytes: ByteLimit(1024)),
    encoded: ByteLimit(500000)), records: ElementLimit(16000), valueBytes: ByteLimit(65536))
proc storageTrie*(value = 7'u8): FullStateTrie =
  ## Build an independent complete mapping with a three-node topology and actual owned values.
  let limits = storageLimits()
  newFullStateTrie([StateEntry(key: storageKey(0), value: @[value]),
    StateEntry(key: storageKey(128), value: @[9'u8])],
    FullStateTrieLimits(trie: limits.codec.trie, writes: ElementLimit(16),
      writeValueBytes: ByteLimit(1024))).value
