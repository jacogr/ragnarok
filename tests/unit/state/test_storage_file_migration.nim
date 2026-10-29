# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit legacy migration preserves source bytes, chain/schema, generation, retained roots and selected context.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[storage_samples, managed_storage_samples]
import ../../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest]
import ../../../src/storage/file/[repository as file_repository, migration as file_migration]
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/database_identity
import ../../../src/codec/state/trie as state_trie
proc main() {.raises.} =
  ## Two independent owners continue after a bounded copy; failed identity/existing-target attempts preserve both.
  let limits = managedStorageLimits()
  let journalLimits = JournalLimits(repository: limits.repository, bytes: limits.journalBytes,
    contextBytes: limits.contextBytes)
  let first = storageTrie(7)
  let second = storageTrie(8)
  var source = default(FileRepository)
  var target = default(ManagedRepository)
  var failed = default(ManagedRepository)
  var sourcePath = "storage-migration-source.wal"
  let targetPath = "storage-migration-target"
  defer:
    if target.opened: discard target.close
    if failed.opened: discard failed.close
    if source.opened: discard source.close
  assert initializeFileRepository(source, sourcePath, default(StorageChainId), journalLimits,
    StorageSchema.FullStateV1) == FileError.None
  let old = source.publish(source.snapshot.value, exportFullTrie(first,
      limits.repository.codec.records).value, [1'u8]).value
  let head = source.publish(old, exportTrieChanges(first, second,
      limits.repository.codec.records).value, [2'u8]).value
  let original = readFile(sourcePath)
  var wrong = default(array[32, byte])
  wrong[0] = 1
  assert migrateFileRepository(source, failed, targetPath, StorageChainId(wrong),
    [head.commitment.root], limits) == FileError.WrongIdentity
  assert migrateFileRepository(source, target, targetPath, default(StorageChainId),
    [old.commitment.root, head.commitment.root], limits) == FileError.None
  assert readFile(sourcePath) == original
  assert uint64(target.snapshot.value.generation) == 2
  assert target.snapshotContext.value == @[2'u8]
  assert restoreHistoricalStateEntries(target.snapshot.value, old.commitment.root,
    limits.repository.codec.trie).value.len == 2
  assert migrateFileRepository(source, failed, targetPath, default(StorageChainId),
    [head.commitment.root], limits) == FileError.AlreadyExists
  assert readFile(sourcePath) == original
  let unchanged = exportTrieChanges(second, second, limits.repository.codec.records).value
  assert uint64(source.publish(head, unchanged, [3'u8]).value.generation) == 3
  assert uint64(target.snapshot.value.generation) == 2 and target.snapshotContext.value == @[2'u8]
  assert target.close == FileError.None
  assert openManagedRepository(target, targetPath, default(StorageChainId), limits,
    StorageSchema.FullStateV1) == FileError.None
  assert uint64(target.snapshot.value.generation) == 2
  assert target.close == FileError.None
  assert source.close == FileError.None
  assert posix.unlink(sourcePath.toCString()) == 0
  removeManagedSample(targetPath, [ManagedEpoch(1)])
try:
  main()
except:
  quit(2)
echo "PASS storage file migration: unchanged legacy source, identity, context, retained roots and independent owners"
