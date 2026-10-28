# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native namespace refusal retains exact selected generation, explicit cleanup and held readers.
import std/assertions
import std/syncio
import ../../support/storage_samples
import ../../support/app_managed_storage_samples
import ../../support/storage_io
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/managed_repository as storage_managed_repository
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/bounded as codec_bounded
proc scenario(skip: cint) {.raises.} =
  ## A consumed SDK refusal cannot silently select staged bytes or roll back a confirmed epoch.
  resetIo()
  let path = "storage_retirement_refusal-" & $skip & "-" & $int(storageProcessId())
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
  armIo(unlinkIo, skip, 1, failedIo)
  let outcome = file.compact(next, [next.commitment.root])
  assert pendingIo() == 0
  assert ioCalls(unlinkIo) == 2
  resetIo()
  assert outcome.error == FileError.None and outcome.value.cleanup == FileError.IoFailure
  assert uint64(outcome.value.epoch) == 2
  assert uint64(file.managedUsage.value.epoch) == 2
  assert readFile(path & "/CURRENT") != current
  assert file.close == FileError.None
  assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  assert uint64(file.managedUsage.value.epoch) == 2
  assert file.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None
  assert file.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None
  assert uint64(file.snapshot.value.generation) == 2
  let entries = restoreStateEntries(file.snapshot.value, next.commitment.root,
      limits.repository.codec.trie).value
  assert entries.len == 2 and entries[0].value == @[8'u8] and entries[1].value == @[9'u8]
  assert file.close == FileError.None and source.close == RepositoryError.None
  let old = restoreStateEntries(held, held.commitment.root, limits.repository.codec.trie).value
  assert old.len == 2 and old[0].value == @[7'u8] and old[1].value == @[9'u8]
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2)])
try:
  scenario(0)
  scenario(1)
except:
  quit(2)
echo "PASS storage_retirement_refusal: consumed native refusal, strict selected restart and explicit idempotent cleanup"
