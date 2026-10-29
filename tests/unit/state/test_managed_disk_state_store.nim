# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit managed DiskStateStore preserves ordinary snapshot identity, policies, context and trusted/local restart.
# @@Verification={"arc":"managed_disk_state_store_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_samples, managed_storage_samples, arc_evidence]
import ../../../src/state/[store, disk_store]
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/node/repository as node_repository
import ../../../src/storage/[database_identity, durability]
import ../../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest]
import ../../../src/codec/state/[trie as state_trie, layout as state_layout]
import ../../../src/codec/bounded
proc cycle(path: string, policy: StateStoreLimits, limits: ManagedLimits) =
  ## Composite native, trie and mutable-handle owners retire after each independent restart.
  var disk = default(DiskStateStore)
  assert openLocalManagedDiskStateStore(disk, path, default(StorageChainId), policy,
      limits).error == DiskStoreError.None
  assert uint64(disk.generation.value) == 3
  assert disk.close == FileError.None
proc main() {.raises.} =
  ## Maintenance changes only physical ownership; ordinary public snapshots retain exact commit identity.
  let limits = managedStorageLimits()
  let policy = StateStoreLimits(trie: limits.repository.codec.trie, writes: ElementLimit(4),
    writeValueBytes: ByteLimit(64))
  var memory = newStateStore([StateEntry(key: storageKey(0), value: @[7'u8]),
    StateEntry(key: storageKey(128), value: @[9'u8])], policy).value
  let seed = memory.snapshot.value
  var disk = default(DiskStateStore)
  let path = "managed-disk-state-store"
  defer:
    if disk.opened: discard disk.close
  assert initializeManagedDiskStateStore(disk, path, default(StorageChainId), seed, limits,
    StorageSchema.FullStateV1).error == DiskStoreError.ContextRequired
  assert initializeManagedDiskStateStore(disk, path, default(StorageChainId), seed, limits,
    StorageSchema.FullStateV1, [1'u8]).error == DiskStoreError.None
  assert sameStateSnapshot(seed, disk.snapshot.value) and uint64(disk.generation.value) == 1
  var candidate = forkStateStore(seed).value
  let changed = candidate.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Put, value: @[8'u8])]).value
  assert disk.commit(seed, changed, [2'u8]).error == DiskStoreError.None
  assert disk.compactDiskStateStore(seed, [changed.commitment.root]).error ==
      DiskStoreError.StaleSnapshot
  let compacted = disk.compactDiskStateStore(changed, [changed.commitment.root]).value
  assert compacted.reclaimedNodes > 0 and compacted.cleanup == FileError.None
  assert sameStateSnapshot(changed, disk.snapshot.value) and uint64(disk.generation.value) == 2
  assert disk.restoreDiskSnapshot(seed.commitment.root, policy).repositoryError ==
      RepositoryError.MissingNode
  assert disk.restoreDiskSnapshot(changed.commitment.root, policy).value.lookup(storageKey(
      0)).value.bytes == @[8'u8]
  assert disk.commit(changed, changed, [3'u8]).error == DiskStoreError.None
  assert sameStateSnapshot(changed, disk.snapshot.value) and uint64(disk.generation.value) == 3
  assert disk.managedDiskUsage.value.journalBytes > uint64(ManagedJournalHeaderBytes)
  assert disk.snapshotContext.value == @[3'u8]
  assert disk.synchronize.value == StorageDurability.FileAndDirectorySynced
  assert disk.close == FileError.None
  assert seed.lookup(storageKey(0)).value.bytes == @[7'u8]
  assert openManagedDiskStateStore(disk, path, default(StorageChainId), seed.commitment.root,
    RepositoryGeneration(3), policy, limits, StorageSchema.FullStateV1).error ==
        DiskStoreError.TrustMismatch
  assert not disk.opened
  var narrow = policy
  narrow.trie.items = ElementLimit(1)
  assert openLocalManagedDiskStateStore(disk, path, default(StorageChainId), narrow,
      limits).error == DiskStoreError.RepositoryFailure
  assert not disk.opened
  for iteration in 0..<10: cycle(path, policy, limits)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(path, policy, limits)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("managed_disk_state_store", 1000, before, after)
  var readOnly = policy
  readOnly.writes = ElementLimit(0)
  let restored = openLocalManagedDiskStateStore(disk, path, default(StorageChainId), readOnly, limits).value
  var fork = forkStateStore(restored).value
  assert fork.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Delete)]).error ==
      StateStoreError.LimitExceeded
  assert disk.commit(restored, restored).error == DiskStoreError.ContextRequired
  assert uint64(disk.generation.value) == 3
  assert disk.close == FileError.None
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
try:
  main()
except:
  quit(2)
echo "PASS managed disk state store: public identity, compaction, contextual restart, policy and retained values"
