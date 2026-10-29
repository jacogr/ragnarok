# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A killed destination copier never changes a live locked legacy source or grants trust to an incomplete target.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[storage_samples, managed_storage_samples, storage_io, storage_crash,
  storage_crash_appends, storage_bootstrap_faults]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/file/repository as file_repository
import ../../../src/storage/managed/repository as managed_repository
import ../../../src/storage/file/migration as file_migration
import ../../../src/storage/database_identity
proc scenario(operation, skip: cint): uint64 {.raises.} =
  ## Parent intentionally retains the source lease across fork; child reads it only and never explicitly closes it.
  resetIo()
  var sourcePath = "migration-crash-source-" & $operation & "-" & $skip & "-" & $int(
      storageProcessId())
  let path = sourcePath & "-target"
  let limits = managedStorageLimits()
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes,
      contextBytes: limits.contextBytes)
  let a = storageTrie(7)
  let b = storageTrie(8)
  var source = default(FileRepository)
  var target = default(FileRepository)
  var competing = default(FileRepository)
  defer:
    abortCrash()
    resetIo()
    if competing.opened: discard competing.close
    if target.opened: discard target.close
    if source.opened: discard source.close
  assert initializeFileRepository(source, sourcePath, default(StorageChainId), journal,
      StorageSchema.FullStateV1) == FileError.None
  let first = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.repository.codec.records).value, [1'u8, 2, 3]).value
  let current = source.publish(first, exportTrieChanges(a, b,
      limits.repository.codec.records).value, [9'u8, 0, 8, 7]).value
  let original = readFile(sourcePath)
  let context = source.snapshotContext.value
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0
  if child == 0:
    if startCrash() != 0: exitCrash(93)
    let copied = migrateFileRepository(source, target, path, default(StorageChainId),
        [first.commitment.root, current.commitment.root], limits)
    if copied != FileError.None: exitCrash(94)
    exitCrash(0)
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096:
    assert receipt == crashCompleted and result > 0 and result < 32
  else:
    assert receipt == crashKilled and result == uint64(skip)+1
  assert source.opened and uint64(source.snapshot.value.generation) == 2
  checkCrashMap(source.snapshot.value, 8)
  assert source.snapshotContext.value == context and readFile(sourcePath) == original
  assert openFileRepository(competing, sourcePath, default(StorageChainId), journal,
      StorageSchema.FullStateV1) == FileError.Busy
  assert not competing.opened # Child death must not release the parent's still-owned source lease.
  let names = ["CURRENT", "CURRENT.next", "snapshot-0000000000000001.bin",
      "journal-0000000000000001.wal", "LOCK"]
  var present: seq[bool] = @[]
  var forensic: seq[string] = @[]
  for name in names:
    let exists = sampleExists(path & "/" & name)
    present.add(exists)
    forensic.add(if exists: readFile(path & "/" & name) else: "")
  assert migrateFileRepository(source, target, path, default(StorageChainId),
      [first.commitment.root, current.commitment.root], limits) == FileError.AlreadyExists
  assert not target.opened
  let visible = sampleExists(path & "/CURRENT")
  let opened = openManagedFileRepository(target, path, default(StorageChainId), limits,
      StorageSchema.FullStateV1)
  if visible:
    assert opened == FileError.None and uint64(target.snapshot.value.generation) == 2
    assert target.snapshotContext.value == context
    checkCrashMap(target.snapshot.value, 8)
    for value in [7'u8, 8'u8]:
      let expected = storageTrie(value)
      let entries = restoreHistoricalStateEntries(target.snapshot.value, expected.commitment.root,
          limits.repository.codec.trie).value
      assert entries.len == 2 and entries[0].value == @[value] and entries[1].value == @[9'u8]
    assert target.close == FileError.None
  else:
    assert opened != FileError.None and not target.opened
  for index, name in names:
    assert sampleExists(path & "/" & name) == present[index]
    if present[index]: assert readFile(path & "/" & name) == forensic[index]
  for value in [7'u8, 8'u8]:
    let expected = storageTrie(value)
    let entries = restoreHistoricalStateEntries(source.snapshot.value, expected.commitment.root,
        limits.repository.codec.trie).value
    assert entries.len == 2 and entries[0].value == @[value] and entries[1].value == @[9'u8]
  assert readFile(sourcePath) == original and source.snapshotContext.value == context
  assert source.close == FileError.None
  removeBootstrapSample(path, true)
  assert posix.unlink(sourcePath.toCString()) == 0
proc main() {.raises.} =
  ## Every actual destination write, barrier and CURRENT rename is independently stopped and killed.
  for operation in [writeIo, syncIo, renameIo]:
    let count = scenario(operation, 4096)
    assert count > 0 and count < 32
    for skip in 0..<int(count):
      assert scenario(operation, cint(skip)) == uint64(skip)+1
try:
  main()
except:
  quit(2)
echo "PASS storage migration crash: every destination boundary, unchanged locked source, context and complete historical maps"
