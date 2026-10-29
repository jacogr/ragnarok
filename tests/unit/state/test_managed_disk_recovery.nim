# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed state restoration keeps layout, exact-prefix repair and independent trust/policy boundaries explicit.
import std/[assertions, syncio]
import ../../support/[storage_samples, managed_storage_samples]
import ../../../src/state/[store, disk_store]
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest]
import ../../../src/storage/node/repository as node_repository
import ../../../src/storage/database_identity
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/codec/bounded
proc main() {.raises.} =
  ## A plausible torn append may be removed only under an exact prefix token, even when later map policy refuses.
  let limits = managedStorageLimits()
  let policy = StateStoreLimits(trie: limits.repository.codec.trie, writes: ElementLimit(4),
    writeValueBytes: ByteLimit(64))
  var memory = newStateStore([StateEntry(key: storageKey(0), value: @[7'u8])], policy).value
  let seed = memory.snapshot.value
  var disk = default(DiskStateStore)
  let path = "managed-disk-recovery"
  defer:
    if disk.opened: discard disk.close
  assert initializeManagedDiskStateStore(disk, path, default(StorageChainId), seed, limits).error ==
      DiskStoreError.None
  let changed = disk.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Put, value: @[8'u8])]).value
  assert disk.close == FileError.None
  let legacy = JournalLimits(repository: limits.repository, bytes: limits.journalBytes)
  assert openDiskStateStore(disk, path, default(StorageChainId), changed.commitment.root,
    RepositoryGeneration(2), policy, legacy).fileError == FileError.IoFailure
  assert not disk.opened
  assert openLocalManagedDiskStateStore(disk, path, default(StorageChainId), policy,
    limits).fileError == FileError.WrongIdentity
  assert not disk.opened
  let journal = path & "/journal-0000000000000001.wal"
  let exact = readFile(journal)
  writeFile(journal, exact & "torn")
  assert openManagedDiskStateStore(disk, path, default(StorageChainId), changed.commitment.root,
    RepositoryGeneration(2), policy, limits).fileError == FileError.InvalidJournal
  assert recoverManagedDiskStateStore(disk, path, default(StorageChainId), seed.commitment.root,
    RepositoryGeneration(1), policy, limits).fileError == FileError.RecoveryMismatch
  assert readFile(journal) == exact & "torn" and not disk.opened
  var narrow = policy
  narrow.trie.items = ElementLimit(0)
  assert recoverManagedDiskStateStore(disk, path, default(StorageChainId), changed.commitment.root,
    RepositoryGeneration(2), narrow, limits).error == DiskStoreError.RepositoryFailure
  assert not disk.opened and readFile(journal) == exact # Authorized repair remains durable even if later restore refuses.
  var readOnly = policy
  readOnly.writes = ElementLimit(0)
  let restored = openManagedDiskStateStore(disk, path, default(StorageChainId),
      changed.commitment.root,
    RepositoryGeneration(2), readOnly, limits).value
  assert restored.lookup(storageKey(0)).value.bytes == @[8'u8]
  assert disk.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Delete)]).stateError ==
      StateStoreError.LimitExceeded
  assert disk.close == FileError.None
  assert openManagedDiskStateStore(disk, path, default(StorageChainId), changed.commitment.root,
    RepositoryGeneration(2), policy, limits).error == DiskStoreError.None
  let next = disk.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Put, value: @[9'u8])]).value
  assert disk.close == FileError.None
  let complete = readFile(journal)
  assert recoverManagedDiskStateStore(disk, path, default(StorageChainId), changed.commitment.root,
    RepositoryGeneration(2), policy, limits).fileError == FileError.RecoveryMismatch
  assert readFile(journal) == complete
  var corrupt = complete
  corrupt[corrupt.high] = char(ord(corrupt[corrupt.high]) xor 1)
  writeFile(journal, corrupt)
  assert recoverManagedDiskStateStore(disk, path, default(StorageChainId), next.commitment.root,
    RepositoryGeneration(3), policy, limits).fileError == FileError.InvalidJournal
  assert readFile(journal) == corrupt and not disk.opened
  assert seed.lookup(storageKey(0)).value.bytes == @[7'u8]
  assert changed.lookup(storageKey(0)).value.bytes == @[8'u8]
  removeManagedSample(path, [ManagedEpoch(1)])
try:
  main()
except:
  quit(2)
echo "PASS managed disk recovery: explicit layout, exact prefix, complete/corrupt successor refusal and inherited policy"
