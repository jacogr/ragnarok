# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed state migration preserves source bytes/ownership, exact context and inherited snapshot policy.
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/storage_samples
import ../../support/app_managed_storage_samples
import ../../../src/state/store as state_store
import ../../../src/state/disk_store as state_disk_store
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/managed_repository as storage_managed_repository
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
proc main() {.raises.} =
  ## Independent source/destination stores share only immutable state data and can publish separate successors.
  let limits = managedStorageLimits()
  let policy = StateStoreLimits(trie: limits.repository.codec.trie, writes: ElementLimit(4),
      writeValueBytes: ByteLimit(64))
  let legacy = JournalLimits(repository: limits.repository, bytes: limits.journalBytes,
      contextBytes: limits.contextBytes)
  var memory = newStateStore([StateEntry(key: storageKey(0), value: @[7'u8])], policy).value
  let seed = memory.snapshot.value
  var source = default(DiskStateStore)
  var target = default(DiskStateStore)
  var failed = default(DiskStateStore)
  var sourcePath = "managed-migration-source.wal"
  let path = "managed-migration-target"
  defer:
    if failed.opened: discard failed.close
    if target.opened: discard target.close
    if source.opened: discard source.close
  assert initializeDiskStateStore(source, sourcePath, default(StorageChainId), seed, legacy,
    StorageSchema.FullStateV1, [1'u8]).error == DiskStoreError.None
  let changed = memory.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Put, value: @[8'u8])]).value
  assert source.commit(seed, changed, [2'u8]).error == DiskStoreError.None
  let original = readFile(sourcePath)
  assert migrateDiskStateStore(source, target, path, default(StorageChainId),
    [seed.commitment.root, changed.commitment.root], limits).error == DiskStoreError.None
  assert sameStateSnapshot(changed, target.snapshot.value)
  assert uint64(target.generation.value) == 2 and target.snapshotContext.value == @[2'u8]
  assert readFile(sourcePath) == original
  assert target.restoreDiskSnapshot(seed.commitment.root, policy).value.lookup(storageKey(
      0)).value.bytes == @[7'u8]
  assert migrateDiskStateStore(source, failed, path, default(StorageChainId),
    [changed.commitment.root], limits).fileError == FileError.AlreadyExists
  assert not failed.opened and readFile(sourcePath) == original
  var sourceFork = forkStateStore(source.snapshot.value).value
  let sourceNext = sourceFork.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Put,
      value: @[9'u8])]).value
  assert source.commit(changed, sourceNext, [3'u8]).error == DiskStoreError.None
  assert target.snapshot.value.lookup(storageKey(0)).value.bytes == @[8'u8]
  assert target.snapshotContext.value == @[2'u8]
  var targetFork = forkStateStore(target.snapshot.value).value
  let targetNext = targetFork.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Put,
      value: @[10'u8])]).value
  assert target.commit(changed, targetNext).error == DiskStoreError.ContextRequired
  assert target.commit(changed, targetNext, [4'u8]).error == DiskStoreError.None
  assert source.snapshot.value.lookup(storageKey(0)).value.bytes == @[9'u8]
  assert uint64(source.generation.value) == 3 and uint64(target.generation.value) == 3
  assert target.close == FileError.None
  assert openLocalManagedDiskStateStore(target, path, default(StorageChainId), policy,
      limits).error == DiskStoreError.None
  assert target.snapshot.value.lookup(storageKey(0)).value.bytes == @[10'u8] and
      target.snapshotContext.value == @[4'u8]
  assert target.close == FileError.None and source.close == FileError.None
  assert posix.unlink(sourcePath.toCString()) == 0
  removeManagedSample(path, [ManagedEpoch(1)])
try:
  main()
except:
  quit(2)
echo "PASS managed state migration: unchanged source, exact policy/context/history and independent durable successors"
