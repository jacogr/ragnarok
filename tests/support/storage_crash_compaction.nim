# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real managed replacement process death preserves one complete selected epoch and independent held readers.
import std/[assertions, syncio]
import ./[storage_samples, managed_storage_samples, storage_io, storage_crash,
  storage_crash_appends, storage_bootstrap_faults]
import ../../src/storage/[full_state_trie, node_repository, node_records, file_repository,
  managed_repository, managed_manifest, database_identity]
import ../../src/codec/bounded
proc compactionCrashCase*(label: string, operation, skip: cint): uint64 {.raises.} =
  ## Prepare a complete obsolete root, then observe only physical compaction after the child's strict open.
  resetIo()
  let path = label & "-" & $operation & "-" & $skip & "-" & $int(storageProcessId())
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
  let originalCurrent = readFile(path & "/CURRENT")
  let originalSnapshot = readFile(path & "/snapshot-0000000000000001.bin")
  let originalJournal = readFile(path & "/journal-0000000000000001.wal")
  assert file.close == FileError.None
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0
  if child == 0:
    if openManagedFileRepository(file, path, default(StorageChainId), limits) !=
        FileError.None: exitCrash(86)
    if startCrash() != 0: exitCrash(87)
    let replaced = file.compact(file.snapshot.value, [current.commitment.root])
    if replaced.error != FileError.None or replaced.value.cleanup != FileError.None: exitCrash(88)
    exitCrash(0)
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert receipt == crashCompleted and result > 0 and result < 32
  else:
    assert receipt == crashKilled and result == uint64(skip)+1
  let visibleCurrent = readFile(path & "/CURRENT")
  let selectedOld = visibleCurrent == originalCurrent
  if operation == writeIo and skip != 4096: assert selectedOld
  if operation == renameIo or operation == unlinkIo or skip == 4096: assert not selectedOld
  for name in ["snapshot-0000000000000001.bin", "journal-0000000000000001.wal"]:
    if sampleExists(path & "/" & name):
      assert readFile(path & "/" & name) == (if name ==
          "snapshot-0000000000000001.bin": originalSnapshot else: originalJournal)
  let names = ["CURRENT.next", "snapshot-0000000000000002.bin", "journal-0000000000000002.wal"]
  var present: seq[bool] = @[]
  var forensic: seq[string] = @[]
  for name in names:
    let exists = sampleExists(path & "/" & name)
    present.add(exists)
    forensic.add(if exists: readFile(path & "/" & name) else: "")
  assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  assert uint64(file.snapshot.value.generation) == 2
  assert uint64(file.managedUsage.value.epoch) == (if selectedOld: 1'u64 else: 2'u64)
  checkCrashMap(file.snapshot.value, 8)
  assert readFile(path & "/CURRENT") == visibleCurrent
  for index, name in names:
    assert sampleExists(path & "/" & name) == present[index]
    if present[index]: assert readFile(path & "/" & name) == forensic[index]
  if selectedOld:
    assert file.discardManagedStaging == FileError.None
    let resumed = file.compact(file.snapshot.value, [current.commitment.root]).value
    assert resumed.cleanup == FileError.None and uint64(resumed.epoch) == 2
  else:
    assert file.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None
  assert file.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None
  assert file.cleanupRetiredEpoch(ManagedEpoch(2)) == FileError.InvalidRetention
  assert file.cleanupRetiredEpoch(ManagedEpoch(3)) == FileError.InvalidRetention
  assert file.close == FileError.None
  assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  assert uint64(file.managedUsage.value.epoch) == 2 and uint64(file.snapshot.value.generation) == 2
  checkCrashMap(file.snapshot.value, 8)
  assert file.close == FileError.None and source.close == RepositoryError.None
  checkCrashMap(held, 7)
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
