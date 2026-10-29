# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real durable StateStore publication retains public identity, fork, policy and trust contracts.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/storage_samples
import ../../../src/state/[store, disk_store]
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/node/repository as node_repository
import ../../../src/storage/[database_identity, durability]
import ../../../src/codec/state/[trie as state_trie, layout as state_layout]
import ../../../src/codec/bounded
proc run() {.raises.} =
  ## Seed from an ordinary snapshot, publish sparse changes, then independently authorize reopen.
  var path = "disk-state-store.db"
  let limits = JournalLimits(repository: storageLimits(), bytes: ByteLimit(1048576))
  let policy = StateStoreLimits(trie: limits.repository.codec.trie,
    writes: ElementLimit(4), writeValueBytes: ByteLimit(64))
  var memory = newStateStore([StateEntry(key: storageKey(0), value: @[7'u8]),
    StateEntry(key: storageKey(128))], policy).value
  let seed = memory.snapshot.value
  let held = seed.lookup(storageKey(0)).value
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close # Every test exit retires the explicit lock owner.
  assert disk.snapshot.error == DiskStoreError.Uninitialized
  assert initializeDiskStateStore(disk, path, default(StorageChainId), seed, limits).error ==
      DiskStoreError.None
  defer: discard posix.unlink(path.toCString())
  assert sameStateSnapshot(seed, disk.snapshot.value)
  assert uint64(disk.generation.value) == 1
  assert sameStateSnapshot(seed, disk.apply([]).value) and uint64(disk.generation.value) == 1
  let bytesBefore = readFile(path)
  let invalid = disk.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Delete, value: @[1'u8])])
  assert invalid.error == DiskStoreError.StateFailure and invalid.stateError ==
      StateStoreError.InvalidWrite
  assert sameStateSnapshot(seed, disk.snapshot.value) and readFile(path) == bytesBefore
  # Actual delta publication keeps input/output buffers and retained historical values independent.
  let changed = disk.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Put, value: @[8'u8]),
    StateWrite(key: storageKey(64), kind: StateWriteKind.Put)]).value
  assert not sameStateSnapshot(seed, changed) and uint64(disk.generation.value) == 2
  assert changed.lookup(storageKey(64)).value.byteLength == 0
  assert held.bytes == @[7'u8] and seed.lookup(storageKey(0)).value.bytes == @[7'u8]
  let noOp = disk.apply([StateWrite(key: storageKey(32), kind: StateWriteKind.Delete)]).value
  assert not sameStateSnapshot(changed, noOp) and uint64(disk.generation.value) == 3
  assert disk.synchronize.value == StorageDurability.FileAndDirectorySynced
  assert disk.close == FileError.None and not disk.opened
  assert disk.close == FileError.Uninitialized
  assert changed.lookup(storageKey(0)).value.bytes == @[8'u8]
  # Wrong trust, chain and narrower complete-map policy never leave an opened owner behind.
  assert openDiskStateStore(disk, path, default(StorageChainId), seed.commitment.root,
    RepositoryGeneration(3), policy, limits).error == DiskStoreError.TrustMismatch
  assert not disk.opened
  assert openDiskStateStore(disk, path, default(StorageChainId), changed.commitment.root,
    RepositoryGeneration(2), policy, limits).error == DiskStoreError.TrustMismatch
  var narrow = policy
  narrow.trie.items = ElementLimit(1)
  assert openDiskStateStore(disk, path, default(StorageChainId), changed.commitment.root,
    RepositoryGeneration(3), narrow, limits).error == DiskStoreError.RepositoryFailure
  assert not disk.opened
  var wrongChain = default(array[32, byte])
  wrongChain[0] = 1
  assert openDiskStateStore(disk, path, StorageChainId(wrongChain), changed.commitment.root,
    RepositoryGeneration(3), policy, limits).fileError == FileError.WrongIdentity
  let restored = openDiskStateStore(disk, path, default(StorageChainId), changed.commitment.root,
    RepositoryGeneration(3), policy, limits).value
  assert not sameStateSnapshot(changed, restored)
  assert restored.lookup(storageKey(0)).value.bytes == @[8'u8]
  assert restored.lookup(storageKey(64)).value.byteLength == 0
  assert disk.apply([StateWrite(key: storageKey(128), kind: StateWriteKind.Delete)]).error ==
      DiskStoreError.None
  assert disk.close == FileError.None
  # Explicit caller-selected zero-write policy survives restoration and private memory forks.
  var readOnly = policy
  readOnly.writes = ElementLimit(0)
  let root = memory.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Put, value: @[8'u8]),
    StateWrite(key: storageKey(64), kind: StateWriteKind.Put),
    StateWrite(key: storageKey(128), kind: StateWriteKind.Delete)]).value.commitment.root
  let bounded = openDiskStateStore(disk, path, default(StorageChainId), root,
    RepositoryGeneration(4), readOnly, limits).value
  var fork = bounded.forkStateStore.value
  assert fork.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Delete)]).error ==
      StateStoreError.LimitExceeded
  assert disk.apply([StateWrite(key: storageKey(0), kind: StateWriteKind.Delete)]).stateError ==
      StateStoreError.LimitExceeded
  assert uint64(disk.generation.value) == 4 and sameStateSnapshot(bounded, disk.snapshot.value)
  assert disk.close == FileError.None and held.bytes == @[7'u8]
try:
  run()
except:
  quit(2) # Fixture IO refusal cannot count as a successful persistence test.
echo "PASS disk state store: durable deltas, trusted restart, policy, forks and retained values"
