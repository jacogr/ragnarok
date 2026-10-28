# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real torn-tail repair fixtures bind destructive truncation to an independently exact complete prefix.
import std/assertions
import std/syncio
import std/posix/posix
import ./storage_samples
import ./app_managed_storage_samples
import ./storage_io
import ../../src/storage/full_state_trie as storage_full_state_trie
import ../../src/storage/node_repository as storage_node_repository
import ../../src/storage/node_records as storage_node_records
import ../../src/storage/file_repository as storage_file_repository
import ../../src/storage/managed_repository as storage_managed_repository
import ../../src/storage/managed_manifest as storage_managed_manifest
import ../../src/storage/database_identity as storage_database_identity
import ../../src/codec/bounded as codec_bounded
proc repairCase*(label: string, managed: bool, skip, failures: cint,
    permanent = false, truncateFault = false): uint64 {.raises.} =
  ## Genuine eight-byte partial appends precede independently authorized repair and complete-map checks.
  resetIo()
  var path = label & "-" & $managed & "-" & $skip & "-" & $int(storageProcessId())
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
    resetIo() # Each case owns its complete fault lifetime and explicit retirement.
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
  resetIo()
  limitWrites(8)
  armIo(writeIo, 1, 1, failedIo)
  assert file.publish(held, exportTrieChanges(a, b, limits.repository.codec.records).value).error ==
      FileError.IoFailure
  assert pendingIo() == 0 and ioCalls(writeIo) == 2
  resetIo()
  assert file.close == FileError.None
  assert readFile(journalPath).len == prefix.len+8
  if truncateFault:
    # Strict startup has no truncation authority, even when a pending truncation fault could be observed.
    armIo(truncateIo, 0, 1, failedIo)
    let opened = if managed:
      openManagedFileRepository(file, path, default(StorageChainId), limits)
    else:
      openFileRepository(file, path, default(StorageChainId), journal)
    assert opened == FileError.InvalidJournal and not file.opened
    assert pendingIo() == 1 and ioCalls(truncateIo) == 0
    resetIo()
  let operation = if truncateFault: truncateIo else: syncIo
  armIo(operation, skip, failures, if permanent: failedIo else: interruptedIo)
  let repaired = if managed:
    recoverManagedFileRepository(file, path, default(StorageChainId), limits,
      RepositoryGeneration(1), held.commitment.root)
  else:
    recoverFileRepository(file, path, default(StorageChainId), journal,
      RepositoryGeneration(1), held.commitment.root)
  result = ioCalls(operation)
  assert pendingIo() == 0, "repair fault boundary did not execute"
  resetIo()
  if permanent:
    # Failed confirmation never returns a live owner, even when truncation already changed visible bytes.
    assert repaired in [FileError.IoFailure, FileError.PublishedUnsynced]
    assert not file.opened
    let visible = readFile(journalPath)
    assert visible.len == prefix.len or visible.len == prefix.len+8
    let opened = if managed:
      openManagedFileRepository(file, path, default(StorageChainId), limits)
    else:
      openFileRepository(file, path, default(StorageChainId), journal)
    if visible.len == prefix.len:
      assert visible == prefix and opened == FileError.None
      assert file.close == FileError.None
    else:
      assert opened == FileError.InvalidJournal and not file.opened
    # The same independent exact prefix can finish confirmation; no complete successor is discarded.
    let confirmed = if managed:
      recoverManagedFileRepository(file, path, default(StorageChainId), limits,
        RepositoryGeneration(1), held.commitment.root)
    else:
      recoverFileRepository(file, path, default(StorageChainId), journal,
        RepositoryGeneration(1), held.commitment.root)
    assert confirmed == FileError.None
  else:
    assert repaired == FileError.None
  assert readFile(journalPath) == prefix and uint64(file.snapshot.value.generation) == 1
  let entries = restoreStateEntries(file.snapshot.value, held.commitment.root,
      limits.repository.codec.trie).value
  assert entries.len == 2 and entries[0].value == @[7'u8] and entries[1].value == @[9'u8]
  assert file.close == FileError.None and source.close == RepositoryError.None
  let retained = restoreStateEntries(held, held.commitment.root, limits.repository.codec.trie).value
  assert retained.len == 2 and retained[0].value == @[7'u8] and retained[1].value == @[9'u8]
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)]) # Exact known fixture epochs alone are removed.
  else:
    assert posix.unlink(path.toCString()) == 0
