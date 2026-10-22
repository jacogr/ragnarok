# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored immutable maps and exact frame bytes qualify strict reopen after a real child process dies.
import std/[assertions, syncio]
import std/posix/posix
import ./[storage_samples, managed_storage_samples, storage_io, storage_crash]
import ../../src/storage/[full_state_trie, node_repository, node_records, journal_codec,
  file_repository, managed_repository, managed_manifest, database_identity]
import ../../src/codec/bounded
proc checkCrashMap*(view: RepositoryView, value: byte) =
  ## An independently constructed complete root and authored leaves constrain every selected or held view.
  let expected = storageTrie(value)
  let restored = restoreStateEntries(view, expected.commitment.root, storageLimits().codec.trie)
  assert restored.error == RepositoryError.None
  let entries = restored.value
  assert entries.len == 2 and entries[0].value == @[value] and entries[1].value == @[9'u8]
proc appendCrashCase*(label: string, managed: bool, operation, skip: cint): uint64 {.raises.} =
  ## Child setup acquires the real lease before arming one publication; the parent owns no native file at fork.
  resetIo()
  var path = label & "-" & $managed & "-" & $skip & "-" & $int(storageProcessId())
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
    abortCrash() # Parent assertion/IO failures still retire only its exact supervised child.
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
  let delta = exportTrieChanges(a, b, limits.repository.codec.records).value
  let encoded = encodeJournalFrame(RepositoryGeneration(2), delta, limits.repository.codec,
      limits.journalBytes).value
  var complete = prefix
  for octet in encoded: complete.add(char(octet))
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0
  if child == 0:
    let opened = if managed:
      openManagedFileRepository(file, path, default(StorageChainId), limits)
    else:
      openFileRepository(file, path, default(StorageChainId), journal)
    if opened != FileError.None or startCrash() != 0: exitCrash(81)
    let published = file.publish(file.snapshot.value, delta)
    if published.error != FileError.None: exitCrash(82)
    exitCrash(0) # Even the completed control exits without explicit close or ARC retirement.
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert receipt == crashCompleted and result > 0 and result < 32
  else:
    assert receipt == crashKilled and result == uint64(skip)+1
  let visible = readFile(journalPath)
  assert visible == prefix or visible == complete
  if operation == writeIo or skip == 4096:
    assert visible == complete # A successful complete write is visible even before its durability receipt.
  else:
    assert operation == syncIo
    assert visible == (if skip < 2: prefix else: complete)
  let opened = if managed:
    openManagedFileRepository(file, path, default(StorageChainId), limits)
  else:
    openFileRepository(file, path, default(StorageChainId), journal)
  assert opened == FileError.None
  let expected = if visible == prefix: 7'u8 else: 8'u8
  assert uint64(file.snapshot.value.generation) == (if expected == 7: 1'u64 else: 2'u64)
  checkCrashMap(file.snapshot.value, expected)
  assert readFile(journalPath) == visible
  assert file.close == FileError.None and source.close == RepositoryError.None
  checkCrashMap(held, 7)
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)])
  else:
    assert posix.unlink(path.toCString()) == 0
