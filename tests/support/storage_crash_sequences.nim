# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Several completed publications before process death retain the exact independently authored visible prefix.
import std/[assertions, syncio]
import std/posix/posix
import ./[storage_samples, managed_storage_samples, storage_io, storage_crash, storage_crash_appends]
import ../../src/storage/[full_state_trie, node_repository, node_records, journal_codec,
  file_repository, managed_repository, managed_manifest, database_identity]
import ../../src/codec/bounded
proc sequenceCrashCase*(label: string, managed: bool, operation, skip: cint): uint64 {.raises.} =
  ## Each full frame is independently encoded before fork; a child never sends a selected head to the parent.
  resetIo()
  var path = label & "-" & $managed & "-" & $operation & "-" & $skip & "-" & $int(storageProcessId())
  let limits = managedStorageLimits()
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes)
  let a = storageTrie(7)
  let values = [8'u8, 10, 11, 12]
  var batches: seq[TrieExport] = @[]
  var frames: seq[seq[byte]] = @[]
  var previous = a
  for index, value in values:
    let next = storageTrie(value)
    let delta = exportTrieChanges(previous, next, limits.repository.codec.records).value
    batches.add(delta)
    frames.add(encodeJournalFrame(RepositoryGeneration(index+2), delta,
        limits.repository.codec, limits.journalBytes).value)
    previous = next
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
  assert file.close == FileError.None
  let journalPath = if managed: path & "/journal-0000000000000001.wal" else: path
  let prefix = readFile(journalPath)
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0
  if child == 0:
    let opened = if managed:
      openManagedFileRepository(file, path, default(StorageChainId), limits)
    else:
      openFileRepository(file, path, default(StorageChainId), journal)
    if opened != FileError.None or startCrash() != 0: exitCrash(84)
    for batch in batches:
      if file.publish(file.snapshot.value, batch).error != FileError.None: exitCrash(85)
    exitCrash(0)
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert receipt == crashCompleted and result == (if operation == writeIo: 4'u64 else: 12'u64)
  else:
    assert receipt == crashKilled and result == uint64(skip)+1
  let completed = if skip == 4096: 4 else:
    (if operation == writeIo: int(skip)+1 else: int(skip) div 3+(if skip mod 3 == 2: 1 else: 0))
  assert completed >= 0 and completed <= values.len
  var exact = prefix
  for index in 0..<completed:
    for octet in frames[index]: exact.add(char(octet))
  assert readFile(journalPath) == exact
  let opened = if managed:
    openManagedFileRepository(file, path, default(StorageChainId), limits)
  else:
    openFileRepository(file, path, default(StorageChainId), journal)
  assert opened == FileError.None
  let view = file.snapshot.value
  assert uint64(view.generation) == uint64(completed)+1
  checkCrashMap(view, if completed == 0: 7'u8 else: values[completed-1])
  for index in 0..<completed:
    let value = if index == 0: 7'u8 else: values[index-1]
    let expected = storageTrie(value)
    let entries = restoreHistoricalStateEntries(view, expected.commitment.root,
        limits.repository.codec.trie).value
    assert entries.len == 2 and entries[0].value == @[value] and entries[1].value == @[9'u8]
  assert readFile(journalPath) == exact
  assert file.close == FileError.None and source.close == RepositoryError.None
  checkCrashMap(held, 7)
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)])
  else:
    assert posix.unlink(path.toCString()) == 0
