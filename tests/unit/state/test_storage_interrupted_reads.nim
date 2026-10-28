# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native interrupted reads retry exactly the same bounded extent while permanent refusal stays explicit.
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
  ## Real strict reopen of each backend survives two injected EINTR results without altering bytes or limits.
  resetIo()
  var path = "storage-interrupted-reads-sdk-" & $managed
  let limits = managedStorageLimits()
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes)
  let a = storageTrie(7)
  var source = newNodeRepository(limits.repository)
  let initial = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(initial, [initial.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  defer:
    resetIo() # No test-only controls may survive cleanup or a failed fixture.
    if file.opened: discard file.close
  if managed:
    assert initializeManagedFileRepository(file, path, default(StorageChainId), selection, [],
        limits) == FileError.None
  else:
    assert initializeFileRepository(file, path, default(StorageChainId), journal) == FileError.None
    discard file.publish(file.snapshot.value, exportFullTrie(a,
        limits.repository.codec.records).value).value
  assert file.close == FileError.None
  let journalPath = if managed: path & "/journal-0000000000000001.wal" else: path
  let original = readFile(journalPath)
  resetIo()
  armIo(readIo, 0, 2, interruptedIo)
  if managed:
    assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  else:
    assert openFileRepository(file, path, default(StorageChainId), journal) == FileError.None
  assert pendingIo() == 0 and ioCalls(readIo) >= 4, "read injection not consumed for backend " & $managed
  assert uint64(file.snapshot.value.generation) == 1
  let held = file.snapshot.value
  let entries = restoreStateEntries(held, a.commitment.root, limits.repository.codec.trie).value
  assert entries.len == 2 and entries[0].value == @[7'u8] and entries[1].value == @[9'u8]
  resetIo()
  assert file.close == FileError.None and readFile(journalPath) == original
  resetIo()
  armIo(readIo, 0, 1, failedIo)
  if managed:
    assert openManagedFileRepository(file, path, default(StorageChainId), limits) ==
        FileError.IoFailure
  else:
    assert openFileRepository(file, path, default(StorageChainId), journal) == FileError.IoFailure
  assert pendingIo() == 0 and ioCalls(readIo) == 1 and not file.opened, "permanent read failure retried or owner leaked"
  resetIo()
  assert readFile(journalPath) == original and source.close == RepositoryError.None
  assert restoreStateEntries(held, a.commitment.root, limits.repository.codec.trie).value.len == 2
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)]) # Clean only the independently owned fixture epoch.
  else:
    assert posix.unlink(path.toCString()) == 0
try:
  scenario(false)
  scenario(true)
except:
  quit(2)
echo "PASS storage interrupted reads: real reopen, bounded retries, permanent refusal and unchanged bytes"
