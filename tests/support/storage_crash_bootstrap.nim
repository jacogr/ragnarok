# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed creator process lifetime grants no implicit overwrite or authority from partial bootstrap files.
import std/[assertions, syncio]
import ./[storage_samples, managed_storage_samples, storage_io, storage_crash,
  storage_crash_appends, storage_bootstrap_faults]
import ../../src/storage/full/state_trie as full_state_trie
import ../../src/storage/node/[repository as node_repository, records as node_records]
import ../../src/storage/file/repository as file_repository
import ../../src/storage/managed/repository as managed_repository
import ../../src/storage/database_identity
import ../../src/codec/bounded
proc bootstrapCrashCase*(label: string, managed: bool, operation, skip: cint): uint64 {.raises.} =
  ## Arm before exclusive creation, then verify preserved forensic names before any independently strict admission.
  resetIo()
  let path = label & "-" & $managed & "-" & $operation & "-" & $skip & "-" & $int(storageProcessId())
  let limits = managedStorageLimits()
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes)
  let a = storageTrie(7)
  var source = newNodeRepository(limits.repository)
  let seed = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(seed, [seed.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  defer:
    abortCrash()
    resetIo()
    if file.opened: discard file.close
  let child = forkCrash(operation, skip)
  assert child >= 0
  if child == 0:
    if startCrash() != 0: exitCrash(89)
    let created = if managed:
      initializeManagedFileRepository(file, path, default(StorageChainId), selection, [], limits)
    else:
      initializeFileRepository(file, path, default(StorageChainId), journal)
    if created != FileError.None: exitCrash(90)
    exitCrash(0)
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert receipt == crashCompleted and result > 0 and result < 32
  else:
    assert receipt == crashKilled and result == uint64(skip)+1
  var names: seq[string] = @[]
  if managed:
    for name in ["CURRENT", "CURRENT.next", "snapshot-0000000000000001.bin",
        "journal-0000000000000001.wal", "LOCK"]:
      names.add(path & "/" & name)
  else:
    names.add(path)
  var present: seq[bool] = @[]
  var forensic: seq[string] = @[]
  for name in names:
    let exists = sampleExists(name)
    present.add(exists)
    forensic.add(if exists: readFile(name) else: "")
  let retry = if managed:
    initializeManagedFileRepository(file, path, default(StorageChainId), selection, [], limits)
  else:
    initializeFileRepository(file, path, default(StorageChainId), journal)
  assert retry == FileError.AlreadyExists and not file.opened
  let visible = if managed: sampleExists(path & "/CURRENT") else: true
  if managed and operation == writeIo and skip != 4096: assert not visible
  if managed and operation == renameIo: assert visible
  let opened = if managed:
    openManagedFileRepository(file, path, default(StorageChainId), limits)
  else:
    openFileRepository(file, path, default(StorageChainId), journal)
  if visible:
    assert opened == FileError.None and file.opened
    assert uint64(file.snapshot.value.generation) == (if managed: 1'u64 else: 0'u64)
    if managed:
      checkCrashMap(file.snapshot.value, 7)
    else:
      assert file.snapshot.value.storedNodes == 0 # An empty repository identity is not an authenticated complete JAM state.
  else:
    assert opened != FileError.None and not file.opened
  for index, name in names:
    assert sampleExists(name) == present[index]
    if present[index]: assert readFile(name) == forensic[index]
  if visible:
    if managed:
      let b = storageTrie(8)
      discard file.publish(file.snapshot.value, exportTrieChanges(a, b,
          limits.repository.codec.records).value).value
      checkCrashMap(file.snapshot.value, 8)
    else:
      discard file.publish(file.snapshot.value, exportFullTrie(a,
          limits.repository.codec.records).value).value
      checkCrashMap(file.snapshot.value, 7)
    assert file.close == FileError.None
  assert source.close == RepositoryError.None
  removeBootstrapSample(path, managed)
