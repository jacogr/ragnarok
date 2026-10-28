# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored immutable maps and exact frame bytes qualify strict reopen after a real child process dies.
import std/assertions
import std/syncio
import std/posix/posix
import ./storage_samples
import ./app_managed_storage_samples
import ./storage_io
import ./storage_crash
import ../../src/storage/full_state_trie as storage_full_state_trie
import ../../src/storage/node_repository as storage_node_repository
import ../../src/storage/node_records as storage_node_records
import ../../src/storage/journal_codec as storage_journal_codec
import ../../src/storage/file_repository as storage_file_repository
import ../../src/storage/managed_repository as storage_managed_repository
import ../../src/storage/managed_manifest as storage_managed_manifest
import ../../src/storage/database_identity as storage_database_identity
import ../../src/codec/bounded as codec_bounded
proc checkCrashMap*(view: RepositoryView, value: byte) =
  ## An independently constructed complete root and authored leaves constrain every selected or held view.
  let expected = storageTrie(value)
  let restored = restoreStateEntries(view, expected.commitment.root, storageLimits().codec.trie)
  assert restored.error == RepositoryError.None
  let entries = restored.value
  assert entries.len == 2 and entries[0].value == @[value] and entries[1].value == @[9'u8]
proc appendCrashCase*(label: string, managed: bool, operation, skip: cint,
    shortWrites = false, contextual = false): uint64 {.raises.} =
  ## Child setup acquires the real lease before arming one publication; the parent owns no native file at fork.
  resetIo()
  var path = label & "-" & $managed & "-" & $skip & "-" & $int(storageProcessId())
  let limits = managedStorageLimits()
  let schema = if contextual: StorageSchema.FullStateV1 else: StorageSchema.FullNodesV1
  let beforeContext: seq[byte] = if contextual: @[1'u8, 2, 3] else: @[]
  let afterContext: seq[byte] = if contextual: @[9'u8, 0, 8, 7] else: @[]
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes,
      contextBytes: if contextual: limits.contextBytes else: ByteLimit(0))
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
    assert initializeManagedFileRepository(file, path, default(StorageChainId), selection,
        beforeContext, limits, schema) == FileError.None
  else:
    assert initializeFileRepository(file, path, default(StorageChainId), journal, schema) == FileError.None
    discard file.publish(file.snapshot.value, exportFullTrie(a,
        limits.repository.codec.records).value, beforeContext).value
  let held = file.snapshot.value
  let heldContext = file.snapshotContext.value
  assert heldContext == beforeContext
  assert file.close == FileError.None
  let journalPath = if managed: path & "/journal-0000000000000001.wal" else: path
  let prefix = readFile(journalPath)
  let delta = exportTrieChanges(a, b, limits.repository.codec.records).value
  let encoded = if contextual:
    encodeContextJournalFrame(RepositoryGeneration(2), delta, afterContext, limits.contextBytes,
        limits.repository.codec, limits.journalBytes).value
  else:
    encodeJournalFrame(RepositoryGeneration(2), delta, limits.repository.codec,
        limits.journalBytes).value
  var complete = prefix
  for octet in encoded: complete.add(char(octet))
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0
  if child == 0:
    let opened = if managed:
      openManagedFileRepository(file, path, default(StorageChainId), limits, schema)
    else:
      openFileRepository(file, path, default(StorageChainId), journal, schema)
    if opened != FileError.None: exitCrash(81)
    if shortWrites: limitWrites(8) # Cap actual kernel progress, never fabricate successful bytes.
    if startCrash() != 0: exitCrash(83)
    let published = file.publish(file.snapshot.value, delta, afterContext)
    if published.error != FileError.None: exitCrash(82)
    exitCrash(0) # Even the completed control exits without explicit close or ARC retirement.
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert receipt == crashCompleted and result > 0 and result < 4096
  else:
    assert receipt == crashKilled and result == uint64(skip)+1
  let visible = readFile(journalPath)
  if shortWrites:
    assert operation == writeIo and result < 4096
    let appended = min(encoded.len, int(result)*8)
    var exact = prefix
    for index in 0..<appended: exact.add(char(encoded[index]))
    assert visible == exact # Every observed partial extent comes from an actual successful native write.
  else:
    assert visible == prefix or visible == complete
    if operation == writeIo or skip == 4096:
      assert visible == complete # A completed full write remains visible before its durability receipt.
    else:
      assert operation == syncIo
      assert visible == (if skip < 2: prefix else: complete)
  let opened = if managed:
    openManagedFileRepository(file, path, default(StorageChainId), limits, schema)
  else:
    openFileRepository(file, path, default(StorageChainId), journal, schema)
  if shortWrites and visible != complete:
    assert opened == FileError.InvalidJournal and not file.opened
    assert readFile(journalPath) == visible
    let wrongGeneration = if managed:
      recoverManagedFileRepository(file, path, default(StorageChainId), limits,
          RepositoryGeneration(0), held.commitment.root, schema)
    else:
      recoverFileRepository(file, path, default(StorageChainId), journal,
          RepositoryGeneration(0), held.commitment.root, schema)
    assert wrongGeneration == FileError.RecoveryMismatch and not file.opened
    assert readFile(journalPath) == visible
    let wrongRoot = if managed:
      recoverManagedFileRepository(file, path, default(StorageChainId), limits,
          RepositoryGeneration(1), b.commitment.root, schema)
    else:
      recoverFileRepository(file, path, default(StorageChainId), journal,
          RepositoryGeneration(1), b.commitment.root, schema)
    assert wrongRoot == FileError.RecoveryMismatch and not file.opened
    assert readFile(journalPath) == visible
    let repaired = if managed:
      recoverManagedFileRepository(file, path, default(StorageChainId), limits,
          RepositoryGeneration(1), held.commitment.root, schema)
    else:
      recoverFileRepository(file, path, default(StorageChainId), journal,
          RepositoryGeneration(1), held.commitment.root, schema)
    assert repaired == FileError.None and readFile(journalPath) == prefix
    checkCrashMap(file.snapshot.value, 7)
    assert file.snapshotContext.value == beforeContext
    discard file.publish(file.snapshot.value, delta, afterContext).value
  else:
    assert opened == FileError.None
    if shortWrites:
      assert file.close == FileError.None
      let rollback = if managed:
        recoverManagedFileRepository(file, path, default(StorageChainId), limits,
            RepositoryGeneration(1), held.commitment.root, schema)
      else:
        recoverFileRepository(file, path, default(StorageChainId), journal,
            RepositoryGeneration(1), held.commitment.root, schema)
      assert rollback == FileError.RecoveryMismatch and not file.opened
      assert readFile(journalPath) == complete
      let strict = if managed:
        openManagedFileRepository(file, path, default(StorageChainId), limits, schema)
      else:
        openFileRepository(file, path, default(StorageChainId), journal, schema)
      assert strict == FileError.None # Complete successors cannot be rolled back by an older repair token.
  let expected = if shortWrites or visible == complete: 8'u8 else: 7'u8
  assert uint64(file.snapshot.value.generation) == (if expected == 7: 1'u64 else: 2'u64)
  checkCrashMap(file.snapshot.value, expected)
  assert file.snapshotContext.value == (if expected == 7: beforeContext else: afterContext)
  assert readFile(journalPath) == (if shortWrites: complete else: visible)
  assert file.close == FileError.None and source.close == RepositoryError.None
  checkCrashMap(held, 7)
  assert heldContext == beforeContext
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)])
  else:
    assert posix.unlink(path.toCString()) == 0
