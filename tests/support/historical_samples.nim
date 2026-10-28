# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact test-owned historical namespace inventories and explicit full-state storage ceilings.
import std/assertions
import std/posix/posix
import ../../src/chain/genesis
import ../../src/state/store
import ../../src/storage/[file_repository, node_repository, node_records, record_codec, managed_repository]
import ../../src/codec/[bounded, state_trie]

func historyHashName*(hash: BlockHash): string =
  ## Encode all header identity bits in one safe local filename component.
  const digits = "0123456789abcdef"
  let source = array[32, byte](hash)
  result = newString(64)
  for index, octet in source:
    result[index*2] = digits[int(octet shr 4)]
    result[index*2+1] = digits[int(octet and 15)]
proc removeHistorySample*(database: string, blocks: openArray[BlockSnapshotResult], ordinals = 0) =
  ## Remove only authored row/record ordinals and known full-hash aliases; unknown filesystem entries never drive cleanup.
  let folder = database & ".history"
  let count = if ordinals > 0: ordinals else: blocks.len+1
  for index in 1..count:
    var row = folder & "/row-" & $index
    var record = folder & "/record-" & $index
    discard posix.unlink(row.toCString())
    discard posix.unlink(record.toCString())
  for saved in blocks:
    var alias = folder & "/block-" & historyHashName(saved.value.blockHash)
    discard posix.unlink(alias.toCString())
  for suffix in ["/identity", "/CLEANUP"]:
    var path = folder & suffix
    discard posix.unlink(path.toCString())
  var path = folder
  assert posix.rmdir(path.toCString()) == 0 or errno() == ENOENT
proc historicalJournalLimits*(policy: StateStoreLimits): JournalLimits =
  ## Finite complete-state graph/context budgets are independent from retained historical file count.
  JournalLimits(repository: RepositoryLimits(codec: RecordLimits(trie: policy.trie,
    records: TrieExportLimits(records: TrieNodeLimit(1000000), valueBytes: ByteLimit(16777216)),
    encoded: ByteLimit(33554432)), records: ElementLimit(2000000), valueBytes: ByteLimit(67108864)),
    bytes: ByteLimit(134217728), contextBytes: ByteLimit(1048576))
proc historicalManagedLimits*(policy: StateStoreLimits): ManagedLimits =
  ## Archive data never expands the bounded live validation/finality graph's root inventory.
  let limits = historicalJournalLimits(policy)
  ManagedLimits(repository: limits.repository, roots: ElementLimit(9),
    snapshotBytes: limits.bytes, journalBytes: limits.bytes, contextBytes: limits.contextBytes)
