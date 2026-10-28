# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared explicit current disk ceilings and scalar-only worker waiting preserve native graph exclusion.
import std/assertions
import std/monotimes
import std/times
import std/posix/posix
import ../../src/app/disk_worker as app_disk_worker
import ../../src/storage/file_repository as storage_file_repository
import ../../src/storage/node_repository as storage_node_repository
import ../../src/storage/node_records as storage_node_records
import ../../src/storage/record_codec as storage_record_codec
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_trie as codec_state_trie
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
