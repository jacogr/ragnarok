# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Finite full paged application policy retains existing complete-state, physical, export and context ceilings.
import ../../state/paged/state as paged_state
import ../../state/disk_store
import ../../storage/full/paged/[store as full_paged_store, stream as full_paged_stream]
import ../../storage/paged/codec as paged_codec
import ../../storage/file/repository as file_repository
import ../../storage/node/records as node_records
import ../../storage/database_identity
import ../../codec/bounded
import ../../codec/state/trie as state_trie
import ../../chain/provider

type PagedApplicationPolicy* = object ## Native streaming and resident export staging remain independent bounded policies.
  contextBytes*: ByteLimit
  native*: FullPagedNativeConfig
  transport*: PagedStateLimits

proc pagedApplicationPolicy*(chain: StorageChainId, root: StateRoot,
    limits: JournalLimits): PagedApplicationPolicy =
  ## Tighten the existing application dataset/export/context controls with explicit paged workspace and operation ceilings.
  let roots = uint64(MaxRetainedBlocks+1)
  let dataset = PagedLimits(entries: ElementLimit(min(uint64(limits.repository.records),
    4194304'u64)), bytes: ByteLimit(min(uint64(limits.bytes), 268435456'u64)))
  let calls = ElementLimit(67108864)
  let reads = ByteLimit(68719476736'u64)
  let records = min(uint64(limits.repository.codec.records.records), 1048576'u64)
  let values = min(uint64(limits.repository.codec.records.valueBytes), 4194304'u64)
  let context = ByteLimit(min(uint64(limits.contextBytes), 4194304'u64))
  # Each multiplicand is capped by a fixed local maximum before the at-most-nine-root staging multiplication.
  let transport = PagedStateLimits(roots: ElementLimit(roots), dataset: dataset,
    staging: TrieExportLimits(records: TrieNodeLimit(roots*records), valueBytes: ByteLimit(roots*values)))
  let native = FullPagedNativeConfig(chain: chain, root: root,
    replayBytes: dataset.bytes, construction: FullPagedConstructionLimits(producerCalls: calls,
      ioCalls: calls, hashes: calls, readBytes: reads, writeBytes: dataset.bytes),
    limits: FullPagedStreamLimits(dataset: dataset, trie: limits.repository.codec.trie,
      roots: ElementLimit(roots), cachePages: ElementLimit(1), contextBytes: context,
      workingBytes: ByteLimit(33554432), scratchBytes: ByteLimit(16777216),
      work: FullPagedWorkLimits(ioCalls: calls, hashes: calls, visits: calls,
        readBytes: reads, writeBytes: dataset.bytes)))
  let inner = if uint64(context) > uint64(PagedDiskContextOverhead): uint64(context)-uint64(
      PagedDiskContextOverhead) else: 0'u64
  PagedApplicationPolicy(contextBytes: ByteLimit(inner), native: native, transport: transport)
