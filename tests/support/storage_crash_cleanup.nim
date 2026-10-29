# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit bounded namespace cleanup after process death never touches selected or farther epoch files.
import std/[assertions, syncio]
import std/posix/posix
import ./[storage_samples, managed_storage_samples, storage_io, storage_crash,
  storage_crash_appends, storage_bootstrap_faults]
import ../../src/storage/full/state_trie as full_state_trie
import ../../src/storage/node/[repository as node_repository, records as node_records]
import ../../src/storage/file/repository as file_repository
import ../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest]
import ../../src/storage/database_identity
import ../../src/codec/bounded
proc cleanupCrashCase*(label: string, retired: bool, operation, skip: cint): uint64 {.raises.} =
  ## Actual refused replacement/retirement prepares forensic files; only test-owned explicit cleanup is observed.
  resetIo()
  let path = label & "-" & $retired & "-" & $operation & "-" & $skip & "-" & $int(storageProcessId())
  let limits = managedStorageLimits()
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
  assert initializeManagedFileRepository(file, path, default(StorageChainId), selection, [],
      limits) == FileError.None
  let held = file.snapshot.value
  let current = file.publish(held, exportTrieChanges(a, b,
      limits.repository.codec.records).value).value
  resetIo()
  if retired:
    armIo(unlinkIo, 0, 2, failedIo)
    let replaced = file.compact(current, [current.commitment.root])
    assert replaced.error == FileError.None and replaced.value.cleanup == FileError.IoFailure
  else:
    armIo(renameIo, 0, 1, failedIo)
    assert file.compact(current, [current.commitment.root]).error == FileError.IoFailure
  assert pendingIo() == 0
  resetIo()
  assert file.close == FileError.None
  let originalCurrent = readFile(path & "/CURRENT")
  let suffix = if retired: "0000000000000002" else: "0000000000000001"
  let selectedNames = ["snapshot-" & suffix & ".bin", "journal-" & suffix & ".wal"]
  var selectedBytes: seq[string] = @[]
  for name in selectedNames: selectedBytes.add(readFile(path & "/" & name))
  var names: seq[string] = @[]
  if retired:
    names = @["journal-0000000000000001.wal", "snapshot-0000000000000001.bin"]
  else:
    names = @["CURRENT.next", "journal-0000000000000002.wal", "snapshot-0000000000000002.bin"]
  var forensic: seq[string] = @[]
  for name in names: forensic.add(readFile(path & "/" & name))
  writeFile(path & "/snapshot-0000000000000003.bin", "farther snapshot")
  writeFile(path & "/journal-0000000000000003.wal", "farther journal")
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0
  if child == 0:
    if openManagedFileRepository(file, path, default(StorageChainId), limits) !=
        FileError.None: exitCrash(95)
    if startCrash() != 0: exitCrash(96)
    let cleaned = if retired: file.cleanupRetiredEpoch(ManagedEpoch(
        1)) else: file.discardManagedStaging
    if cleaned != FileError.None: exitCrash(97)
    exitCrash(0)
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert receipt == crashCompleted and result == uint64(names.len)
  else:
    assert receipt == crashKilled and result == uint64(skip)+1
  let removed = if skip == 4096: names.len else: int(skip)+1
  for index, name in names:
    assert sampleExists(path & "/" & name) == (index >= removed)
    if index >= removed: assert readFile(path & "/" & name) == forensic[index]
  assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  assert uint64(file.managedUsage.value.epoch) == (if retired: 2'u64 else: 1'u64)
  assert uint64(file.snapshot.value.generation) == 2
  checkCrashMap(file.snapshot.value, 8)
  assert readFile(path & "/CURRENT") == originalCurrent
  for index, name in selectedNames: assert readFile(path & "/" & name) == selectedBytes[index]
  for index, name in names:
    assert sampleExists(path & "/" & name) == (index >= removed)
    if index >= removed: assert readFile(path & "/" & name) == forensic[index]
  for repetition in 0..<2:
    let cleaned = if retired: file.cleanupRetiredEpoch(ManagedEpoch(
        1)) else: file.discardManagedStaging
    assert cleaned == FileError.None
  assert file.cleanupRetiredEpoch(ManagedEpoch(if retired: 2 else: 1)) == FileError.InvalidRetention
  assert file.cleanupRetiredEpoch(ManagedEpoch(3)) == FileError.InvalidRetention
  assert readFile(path & "/CURRENT") == originalCurrent
  for index, name in selectedNames: assert readFile(path & "/" & name) == selectedBytes[index]
  assert readFile(path & "/snapshot-0000000000000003.bin") == "farther snapshot"
  assert readFile(path & "/journal-0000000000000003.wal") == "farther journal"
  assert file.close == FileError.None and source.close == RepositoryError.None
  checkCrashMap(held, 7)
  for name in ["snapshot-0000000000000003.bin", "journal-0000000000000003.wal"]:
    var childPath = path & "/" & name
    assert posix.unlink(childPath.toCString()) == 0
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
