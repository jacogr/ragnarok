# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual cross-process cooperative leases remain Busy before SIGKILL and reopen only after kernel retirement.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[storage_samples, managed_storage_samples, storage_io, storage_crash, storage_crash_appends]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest]
import ../../../src/storage/database_identity
import ../../../src/codec/bounded
proc scenario(managed, parked: bool) {.raises.} =
  ## Parent closes its original owner before fork, so the stopped child alone owns the acquired kernel lease.
  resetIo()
  var path = "process-lease-" & $managed & "-" & $parked & "-" & $int(storageProcessId())
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
    abortCrash()
    resetIo()
    if other.opened: discard other.close
    if file.opened: discard file.close
  if managed:
    assert initializeManagedFileRepository(file, path, default(StorageChainId), selection, [],
        limits) == FileError.None
  else:
    assert initializeFileRepository(file, path, default(StorageChainId), journal) == FileError.None
    discard file.publish(file.snapshot.value, exportFullTrie(a,
        limits.repository.codec.records).value).value
  let held = file.snapshot.value
  assert file.close == FileError.None
  let journalPath = if managed: path & "/journal-0000000000000001.wal" else: path
  let original = readFile(journalPath)
  resetIo()
  let child = forkCrash(lockIo, cint(if parked: 0 else: 4096))
  assert child >= 0
  if child == 0:
    if startCrash() != 0: exitCrash(98)
    let opened = if managed:
      openManagedFileRepository(file, path, default(StorageChainId), limits)
    else:
      openFileRepository(file, path, default(StorageChainId), journal)
    if opened != FileError.None: exitCrash(99)
    exitCrash(0)
  if parked:
    assert waitCrash() == crashStopped and crashCount() == 1
    let busy = if managed:
      openManagedFileRepository(other, path, default(StorageChainId), limits)
    else:
      openFileRepository(other, path, default(StorageChainId), journal)
    assert busy == FileError.Busy and not other.opened
    assert waitCrash() == crashStopped and crashCount() == 1
    assert forkCrash(lockIo, 0) == -1 and finishCrash(0) == crashInvalid
    assert finishCrash() == crashKilled and crashCount() == 1
  else:
    assert finishCrash() == crashCompleted and crashCount() == 1
  assert finishCrash() == crashInvalid and waitCrash() == crashInvalid
  let opened = if managed:
    openManagedFileRepository(other, path, default(StorageChainId), limits)
  else:
    openFileRepository(other, path, default(StorageChainId), journal)
  assert opened == FileError.None and uint64(other.snapshot.value.generation) == 1
  checkCrashMap(other.snapshot.value, 7)
  assert readFile(journalPath) == original
  assert other.close == FileError.None and source.close == RepositoryError.None
  checkCrashMap(held, 7)
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)])
  else:
    assert posix.unlink(path.toCString()) == 0
proc main() {.raises.} =
  ## Both ordinary completed controls and held-stop contention use actual cooperative kernel locks.
  for managed in [false, true]:
    scenario(managed, false)
    scenario(managed, true)
try:
  main()
except:
  quit(2)
echo "PASS process lease crash: actual cross-process Busy, witnessed held stop, SIGKILL release and exact restart"
