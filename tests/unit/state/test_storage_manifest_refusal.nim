# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native namespace refusal retains exact selected generation, explicit cleanup and held readers.
import std/[assertions, syncio]
import ../../support/[storage_samples, managed_storage_samples, storage_io]
import ../../../src/storage/[full_state_trie, node_repository, node_records, file_repository,
  managed_repository, managed_manifest, database_identity]
import ../../../src/codec/bounded
proc scenario(skip: cint) {.raises.} =
  ## A consumed SDK refusal cannot silently select staged bytes or roll back a confirmed epoch.
  resetIo()
  let path = "storage_manifest_refusal-" & $skip & "-" & $int(storageProcessId())
  let limits = managedStorageLimits()
  let a = storageTrie(7)
  let b = storageTrie(8)
  var source = newNodeRepository(limits.repository)
  let seed = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(seed, [seed.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  defer:
    resetIo() # Retire test-owned resources without carrying injection into fixture cleanup.
    if file.opened: discard file.close
  assert initializeManagedFileRepository(file, path, default(StorageChainId), selection, [],
      limits) == FileError.None
  let held = file.snapshot.value
  let next = file.publish(held, exportTrieChanges(a, b,
      limits.repository.codec.records).value).value
  let current = readFile(path & "/CURRENT")
  resetIo() # Count only the replacement operation, excluding initial manifest installation.
  armIo(renameIo, skip, 1, failedIo)
  let outcome = file.compact(next, [next.commitment.root])
  assert pendingIo() == 0, "namespace witness 33"
  assert ioCalls(renameIo) == 1, "namespace witness 34"
  resetIo()
  assert outcome.error == FileError.IoFailure, "namespace witness 36"
  assert file.snapshot.error == FileError.RecoveryRequired, "namespace witness 37"
  assert readFile(path & "/CURRENT") == current, "namespace witness 38"
  let pending = readFile(path & "/CURRENT.next")
  let stagedSnapshot = readFile(path & "/snapshot-0000000000000002.bin")
  let stagedJournal = readFile(path & "/journal-0000000000000002.wal")
  assert file.close == FileError.None, "namespace witness 42"
  assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None, "namespace witness 43"
  assert uint64(file.managedUsage.value.epoch) == 1, "namespace witness 44"
  assert readFile(path & "/CURRENT.next") == pending, "namespace witness 45"
  assert readFile(path & "/snapshot-0000000000000002.bin") == stagedSnapshot, "namespace witness 46"
  assert readFile(path & "/journal-0000000000000002.wal") == stagedJournal, "namespace witness 47"
  assert file.discardManagedStaging == FileError.None, "namespace witness 48"
  assert file.compact(file.snapshot.value, [next.commitment.root]).value.cleanup == FileError.None, "namespace witness 49"
  assert uint64(file.snapshot.value.generation) == 2, "namespace witness 50"
  let entries = restoreStateEntries(file.snapshot.value, next.commitment.root,
      limits.repository.codec.trie).value
  assert entries.len == 2 and entries[0].value == @[8'u8] and entries[1].value == @[9'u8], "namespace witness 53"
  assert file.close == FileError.None and source.close == RepositoryError.None, "namespace witness 54"
  let old = restoreStateEntries(held, held.commitment.root, limits.repository.codec.trie).value
  assert old.len == 2 and old[0].value == @[7'u8] and old[1].value == @[9'u8], "namespace witness 56"
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
try:
  scenario(0)
except:
  quit(2)
echo "PASS storage_manifest_refusal: consumed native refusal, strict selected restart and explicit idempotent cleanup"
