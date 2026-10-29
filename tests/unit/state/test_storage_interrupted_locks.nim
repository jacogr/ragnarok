# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native lease interruptions preserve nonblocking competition and exact one-owner retirement.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[storage_samples, managed_storage_samples, storage_io]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest]
import ../../../src/storage/database_identity
import ../../../src/codec/bounded
proc scenario(managed: bool) {.raises.} =
  ## Both layouts resume acquisition/unlock, retain real Busy, and stop permanently refused operations.
  resetIo()
  var path = "storage-locks-" & $managed & "-" & $int(storageProcessId())
  let limits = managedStorageLimits()
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes)
  let a = storageTrie(7)
  var source = newNodeRepository(limits.repository)
  let seed = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(seed, [seed.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  var other = default(FileRepository)
  defer:
    resetIo() # No fault configuration may escape a fixture's explicit native lifetime.
    if other.opened: discard other.close
    if file.opened: discard file.close
  armIo(lockIo, 0, 2, interruptedIo)
  if managed:
    assert initializeManagedFileRepository(file, path, default(StorageChainId), selection, [],
        limits) == FileError.None
  else:
    assert initializeFileRepository(file, path, default(StorageChainId), journal) == FileError.None
  assert pendingIo() == 0 and ioCalls(lockIo) == 3
  resetIo()
  if not managed:
    discard file.publish(file.snapshot.value, exportFullTrie(a,
        limits.repository.codec.records).value).value
  let held = file.snapshot.value
  let journalPath = if managed: path & "/journal-0000000000000001.wal" else: path
  let original = readFile(journalPath)
  armIo(lockIo, 0, 2, interruptedIo)
  let busy = if managed:
    openManagedFileRepository(other, path, default(StorageChainId), limits)
  else:
    openFileRepository(other, path, default(StorageChainId), journal)
  assert busy == FileError.Busy and not other.opened
  assert pendingIo() == 0 and ioCalls(lockIo) == 3
  resetIo()
  armIo(lockIo, 0, 2, interruptedIo)
  assert file.close == FileError.None
  assert pendingIo() == 0 and ioCalls(lockIo) == 3
  resetIo()
  armIo(lockIo, 0, 1, failedIo)
  let refused = if managed:
    openManagedFileRepository(other, path, default(StorageChainId), limits)
  else:
    openFileRepository(other, path, default(StorageChainId), journal)
  assert refused == FileError.IoFailure and not other.opened
  assert pendingIo() == 0 and ioCalls(lockIo) == 1
  resetIo()
  if managed:
    assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  else:
    assert openFileRepository(file, path, default(StorageChainId), journal) == FileError.None
  armIo(lockIo, 0, 1, failedIo)
  assert file.close == FileError.IoFailure and not file.opened
  assert pendingIo() == 0 # Closing the actual descriptor must still release the kernel lease after refused unlock.
  resetIo()
  if managed:
    assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  else:
    assert openFileRepository(file, path, default(StorageChainId), journal) == FileError.None
  let entries = restoreStateEntries(file.snapshot.value, held.commitment.root,
      limits.repository.codec.trie).value
  assert entries.len == 2 and entries[0].value == @[7'u8] and entries[1].value == @[9'u8]
  assert readFile(journalPath) == original
  assert file.close == FileError.None and source.close == RepositoryError.None
  let old = restoreStateEntries(held, held.commitment.root, limits.repository.codec.trie).value
  assert old.len == 2 and old[0].value == @[7'u8] and old[1].value == @[9'u8]
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)])
  else:
    assert posix.unlink(path.toCString()) == 0
try:
  scenario(false)
  scenario(true)
except:
  quit(2)
echo "PASS storage interrupted locks: actual nonblocking Busy, resumed leases, refused unlock and exact restart"
