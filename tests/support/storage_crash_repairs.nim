# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Only an independently exact complete prefix permits truncation before a real recovery process dies.
import std/[assertions, syncio]
import std/posix/posix
import ./[storage_samples, managed_storage_samples, storage_io, storage_crash, storage_crash_appends]
import ../../src/storage/full/state_trie as full_state_trie
import ../../src/storage/node/[repository as node_repository, records as node_records]
import ../../src/storage/file/repository as file_repository
import ../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest]
import ../../src/storage/database_identity
import ../../src/codec/bounded
proc repairCrashCase*(label: string, managed: bool, operation, skip: cint): uint64 {.raises.} =
  ## A genuine short failed append creates the tail; child recovery receives a caller-selected exact token.
  resetIo()
  var path = label & "-" & $managed & "-" & $operation & "-" & $skip & "-" & $int(storageProcessId())
  let limits = managedStorageLimits()
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes)
  let a = storageTrie(7)
  let b = storageTrie(8)
  var source = newNodeRepository(limits.repository)
  let seed = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(seed, [seed.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  defer:
    abortCrash()
    resetIo()
    if file.opened: discard file.close
  if managed:
    assert initializeManagedFileRepository(file, path, default(StorageChainId), selection, [],
        limits) == FileError.None
  else:
    assert initializeFileRepository(file, path, default(StorageChainId), journal) == FileError.None
    discard file.publish(file.snapshot.value, exportFullTrie(a,
        limits.repository.codec.records).value).value
  let held = file.snapshot.value
  let journalPath = if managed: path & "/journal-0000000000000001.wal" else: path
  let prefix = readFile(journalPath)
  let delta = exportTrieChanges(a, b, limits.repository.codec.records).value
  resetIo()
  limitWrites(8)
  armIo(writeIo, 1, 1, failedIo)
  assert file.publish(held, delta).error == FileError.IoFailure
  assert pendingIo() == 0 and ioCalls(writeIo) == 2
  resetIo()
  assert file.close == FileError.None
  let torn = readFile(journalPath)
  assert torn.len == prefix.len+8
  let child = forkCrash(operation, skip)
  assert child >= 0
  if child == 0:
    if startCrash() != 0: exitCrash(91)
    let repaired = if managed:
      recoverManagedFileRepository(file, path, default(StorageChainId), limits,
          RepositoryGeneration(1), held.commitment.root)
    else:
      recoverFileRepository(file, path, default(StorageChainId), journal,
          RepositoryGeneration(1), held.commitment.root)
    if repaired != FileError.None: exitCrash(92)
    exitCrash(0)
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert receipt == crashCompleted and result > 0 and result < 32
  else:
    assert receipt == crashKilled and result == uint64(skip)+1
  let visible = readFile(journalPath)
  assert visible == torn or visible == prefix
  if operation == truncateIo or skip == 4096: assert visible == prefix
  let opened = if managed:
    openManagedFileRepository(file, path, default(StorageChainId), limits)
  else:
    openFileRepository(file, path, default(StorageChainId), journal)
  if visible == torn:
    assert opened == FileError.InvalidJournal and not file.opened
  else:
    assert opened == FileError.None and uint64(file.snapshot.value.generation) == 1
    checkCrashMap(file.snapshot.value, 7)
    assert file.close == FileError.None
  assert readFile(journalPath) == visible
  let mismatch = if managed:
    recoverManagedFileRepository(file, path, default(StorageChainId), limits,
        RepositoryGeneration(1), b.commitment.root)
  else:
    recoverFileRepository(file, path, default(StorageChainId), journal,
        RepositoryGeneration(1), b.commitment.root)
  assert mismatch == FileError.RecoveryMismatch and not file.opened
  assert readFile(journalPath) == visible
  let confirmed = if managed:
    recoverManagedFileRepository(file, path, default(StorageChainId), limits,
        RepositoryGeneration(1), held.commitment.root)
  else:
    recoverFileRepository(file, path, default(StorageChainId), journal,
        RepositoryGeneration(1), held.commitment.root)
  assert confirmed == FileError.None and readFile(journalPath) == prefix
  checkCrashMap(file.snapshot.value, 7)
  let next = file.publish(file.snapshot.value, delta).value
  assert uint64(next.generation) == 2
  checkCrashMap(next, 8)
  assert file.close == FileError.None
  let strict = if managed:
    openManagedFileRepository(file, path, default(StorageChainId), limits)
  else:
    openFileRepository(file, path, default(StorageChainId), journal)
  assert strict == FileError.None and uint64(file.snapshot.value.generation) == 2
  checkCrashMap(file.snapshot.value, 8)
  assert file.close == FileError.None and source.close == RepositoryError.None
  checkCrashMap(held, 7)
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)])
  else:
    assert posix.unlink(path.toCString()) == 0
