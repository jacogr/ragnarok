# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared explicit current disk ceilings and scalar-only worker waiting preserve native graph exclusion.
import std/[assertions, monotimes, times]
import std/posix/posix
import ../../src/app/disk/worker as disk_worker
import ../../src/storage/file/repository as file_repository
import ../../src/storage/node/[repository as node_repository, records as node_records]
import ../../src/storage/record_codec
import ../../src/codec/bounded
import ../../src/codec/state/trie as state_trie
proc currentDiskLimits*(): JournalLimits =
  ## Explicit broad fixture ceilings bound all physical records, individual batches and history context.
  JournalLimits(repository: RepositoryLimits(codec: RecordLimits(trie: StateTrieLimits(
    items: ElementLimit(100000), perValue: ByteLimit(1048576), totalValueBytes: ByteLimit(16777216),
    nodes: TrieNodeLimit(1000000)), records: TrieExportLimits(records: TrieNodeLimit(1000000),
      valueBytes: ByteLimit(16777216)), encoded: ByteLimit(33554432)),
    records: ElementLimit(2000000), valueBytes: ByteLimit(67108864)),
    bytes: ByteLimit(134217728), contextBytes: ByteLimit(1048576))
proc waitCurrentDiskDone*(worker: var DiskPublicationWorker) =
  ## Only scalar worker state is touched while every leased ARC alias remains frozen.
  let started = getMonoTime()
  while worker.phase != DiskWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20, "bounded native completion"
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Yield under a monotonic bounded test deadline.
