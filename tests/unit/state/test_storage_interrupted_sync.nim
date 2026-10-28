# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual file and directory barriers must finish after consumed EINTR without publishing uncertainty.
import std/assertions
import std/syncio
import std/posix/posix
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
import ../../../src/codec/state_trie as codec_state_trie
proc scenario(managed: bool) {.raises.} =
  ## Both layouts keep exact generation/maps and held readers through interrupted publication and sync.
  resetIo()
  var path = "storage-sync-checked-" & $managed
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
    resetIo() # Faults never leak into retirement or another scenario.
    if file.opened: discard file.close
  armIo(syncIo, 0, 2, interruptedIo)
  if managed:
    assert initializeManagedFileRepository(file, path, default(StorageChainId), selection, [],
        limits) == FileError.None
  else:
    assert initializeFileRepository(file, path, default(StorageChainId), journal) == FileError.None
  assert pendingIo() == 0 and ioCalls(syncIo) >= 4, "initial/open barriers: " & $managed &
      " calls=" & $ioCalls(syncIo) & " pending=" & $pendingIo()
  resetIo()
  if not managed:
    discard file.publish(file.snapshot.value, exportFullTrie(a,
        limits.repository.codec.records).value).value
  let held = file.snapshot.value
  resetIo() # The legacy seed publication is preparation, outside this observed operation.
  armIo(syncIo, 2, 2, interruptedIo) # Interrupt the post-append barrier after both real prior barriers.
  let next = file.publish(held, exportTrieChanges(a, b,
      limits.repository.codec.records).value).value
  assert pendingIo() == 0 and ioCalls(syncIo) == 5, "publication barriers: " & $managed &
      " calls=" & $ioCalls(syncIo)
  assert uint64(next.generation) == 2
  resetIo()
  let journalPath = if managed: path & "/journal-0000000000000001.wal" else: path
  let unchanged = readFile(journalPath)
  armIo(syncIo, 1, 2, interruptedIo) # A real file barrier precedes interrupted directory synchronization.
  discard file.synchronize.value
  assert pendingIo() == 0 and ioCalls(syncIo) == 4, "directory barriers: " & $managed & " calls=" &
      $ioCalls(syncIo)
  resetIo()
  assert file.close == FileError.None
  armIo(syncIo, 0, 2, interruptedIo)
  if managed:
    assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  else:
    assert openFileRepository(file, path, default(StorageChainId), journal) == FileError.None
  assert pendingIo() == 0 and ioCalls(syncIo) >= 4, "initial/open barriers: " & $managed &
      " calls=" & $ioCalls(syncIo) & " pending=" & $pendingIo()
  resetIo()
  assert uint64(file.snapshot.value.generation) == 2
  let entries = restoreStateEntries(file.snapshot.value, next.commitment.root,
      limits.repository.codec.trie).value
  assert entries.len == 2 and entries[0].value == @[8'u8] and entries[1].value == @[9'u8]
  assert readFile(journalPath) == unchanged
  assert file.close == FileError.None and source.close == RepositoryError.None
  let old = restoreStateEntries(held, held.commitment.root, limits.repository.codec.trie).value
  assert old.len == 2 and old[0].value == @[7'u8] and old[1].value == @[9'u8]
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)]) # Retire only exact fixture files after all assertions.
  else:
    assert posix.unlink(path.toCString()) == 0
try:
  scenario(false)
  scenario(true)
except:
  quit(2)
echo "PASS storage interrupted sync: genuine file/directory barriers, durable publication and unchanged maps"
