# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Injected native fsync refusal must poison publication without revoking old readers or guessing repair authority.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[storage_samples, managed_storage_samples, storage_io]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest]
import ../../../src/storage/database_identity
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
proc check(view: RepositoryView, expected: byte) =
  ## Independently compare every complete value after uncertain IO and native owner retirement.
  let entries = restoreStateEntries(view, view.commitment.root, storageLimits().codec.trie).value
  assert entries.len == 2 and entries[0].value == @[expected] and entries[1].value == @[9'u8]
proc scenario(managed: bool) {.raises.} =
  ## Real writes precede one injected refused barrier; strict reopen may admit the complete visible successor.
  resetIo()
  var path = "storage-sync-failure-" & $managed
  let limits = managedStorageLimits()
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes)
  let a = storageTrie(7)
  let b = storageTrie(8)
  var source = newNodeRepository(limits.repository)
  let initial = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(initial, [initial.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  defer:
    resetIo() # No pending injection may leak into cleanup or another native suite.
    if file.opened: discard file.close
  if managed:
    assert initializeManagedFileRepository(file, path, default(StorageChainId), selection, [],
        limits) == FileError.None
  else:
    assert initializeFileRepository(file, path, default(StorageChainId), journal) == FileError.None
    discard file.publish(file.snapshot.value, exportFullTrie(a,
        limits.repository.codec.records).value).value
  let held = file.snapshot.value
  resetIo()
  armIo(syncIo, 2, 1, failedIo) # Both layouts confirm two prior boundaries before the actual append.
  let refused = file.publish(held, exportTrieChanges(a, b, limits.repository.codec.records).value)
  assert refused.error == FileError.PublishedUnsynced
  assert ioCalls(syncIo) == 3 and pendingIo() == 0
  assert file.snapshot.error == FileError.RecoveryRequired
  assert file.synchronize.error == FileError.RecoveryRequired
  check(held, 7)
  resetIo()
  assert file.close == FileError.None
  if managed:
    assert recoverManagedFileRepository(file, path, default(StorageChainId), limits,
      RepositoryGeneration(1), held.commitment.root) == FileError.RecoveryMismatch
    assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  else:
    assert recoverFileRepository(file, path, default(StorageChainId), journal,
      RepositoryGeneration(1), held.commitment.root) == FileError.RecoveryMismatch
    assert openFileRepository(file, path, default(StorageChainId), journal) == FileError.None
  assert uint64(file.snapshot.value.generation) == 2
  check(file.snapshot.value, 8)
  # A separately refused synchronization must also poison a live owner, without appending any frame.
  let next = file.snapshot.value
  resetIo()
  armIo(syncIo, 0, 1, failedIo)
  let failedSync = if managed: FileError.PublishedUnsynced else: FileError.IoFailure
  assert file.synchronize.error == failedSync # Preserve each backend's existing barrier-refusal distinction.
  assert pendingIo() == 0 and ioCalls(syncIo) == 1
  assert file.snapshot.error == FileError.RecoveryRequired
  check(next, 8)
  resetIo()
  assert file.close == FileError.None
  if managed:
    assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  else:
    assert openFileRepository(file, path, default(StorageChainId), journal) == FileError.None
  let journalPath = if managed: path & "/journal-0000000000000001.wal" else: path
  let unchanged = readFile(journalPath)
  resetIo()
  armIo(syncIo, 1, 1, failedIo) # The file barrier succeeds; the following directory barrier refuses.
  assert file.synchronize.error == FileError.IoFailure
  assert pendingIo() == 0 and ioCalls(syncIo) == 2
  assert file.snapshot.error == FileError.RecoveryRequired
  resetIo()
  assert file.close == FileError.None and readFile(journalPath) == unchanged
  assert source.close == RepositoryError.None
  check(held, 7)
  check(next, 8)
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)]) # Fixture cleanup names only its own exact epoch.
  else:
    assert posix.unlink(path.toCString()) == 0
try:
  scenario(false)
  scenario(true)
except:
  quit(2)
echo "PASS storage sync failures: genuine writes, injected barrier refusal, poisoned owners and exact recovery trust"
