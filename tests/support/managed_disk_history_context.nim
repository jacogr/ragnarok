# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared finite managed history policies preserve the exact StateStore graph ceilings in maintenance tests.
import ../../src/state/store
import ../../src/storage/managed/repository as managed_repository
import ../../src/storage/node/[repository as node_repository, records as node_records]
import ../../src/storage/record_codec
import ../../src/codec/bounded
import ../../src/codec/state/trie as state_trie
proc managedHistoryLimits*(policy: StateStoreLimits): ManagedLimits =
  ## Independent physical and file budgets fit nine retained structural history fixtures.
  ManagedLimits(repository: RepositoryLimits(codec: RecordLimits(trie: policy.trie,
    records: TrieExportLimits(records: TrieNodeLimit(100000), valueBytes: ByteLimit(1048576)),
    encoded: ByteLimit(4194304)), records: ElementLimit(100000), valueBytes: ByteLimit(16777216)),
    roots: ElementLimit(9), snapshotBytes: ByteLimit(33554432), journalBytes: ByteLimit(33554432),
    contextBytes: ByteLimit(1048576))
