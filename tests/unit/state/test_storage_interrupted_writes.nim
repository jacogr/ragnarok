# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Interrupted real short writes preserve exact frame bytes; later partial EIO requires explicit prefix repair.
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/storage_samples
import ../../support/app_managed_storage_samples
import ../../support/storage_io
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/journal_codec as storage_journal_codec
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/managed_repository as storage_managed_repository
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
proc check(view: RepositoryView, expected: byte) =
  ## Held views remain complete and independent across retry, poisoned owner and explicit repair.
  let entries = restoreStateEntries(view, view.commitment.root, storageLimits().codec.trie).value
  assert entries.len == 2 and entries[0].value == @[expected] and entries[1].value == @[9'u8]
proc scenario(managed: bool) {.raises.} =
  ## Both backends resume after actual8-byte progress plus two EINTR returns, without duplication.
  resetIo()
  var path = "storage-write-interruptions-fresh-" & $managed
  let limits = managedStorageLimits()
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes)
  let a = storageTrie(7)
  let b = storageTrie(8)
  let c = storageTrie(10)
  var source = newNodeRepository(limits.repository)
  let initial = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.repository.codec.records).value).value
  let selected = selectRepositoryRoots(initial, [initial.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  defer:
    resetIo() # Fault controls and short-write caps never survive a fixture boundary.
    if file.opened: discard file.close
  if managed:
    assert initializeManagedFileRepository(file, path, default(StorageChainId), selected, [],
        limits) == FileError.None
  else:
    assert initializeFileRepository(file, path, default(StorageChainId), journal) == FileError.None
    discard file.publish(file.snapshot.value, exportFullTrie(a,
        limits.repository.codec.records).value).value
  let held = file.snapshot.value
  let journalPath = if managed: path & "/journal-0000000000000001.wal" else: path
  let original = readFile(journalPath)
  let delta = exportTrieChanges(a, b, limits.repository.codec.records).value
  let frame = encodeJournalFrame(RepositoryGeneration(2), delta, limits.repository.codec,
      limits.journalBytes).value
  resetIo()
  limitWrites(8)
  armIo(writeIo, 1, 2, interruptedIo)
  let next = file.publish(held, delta).value
  assert pendingIo() == 0 and ioCalls(writeIo) > 3, "short progress/EINTR path was not exercised"
  resetIo()
  assert uint64(next.generation) == 2
  var expected = original
  for octet in frame:
    expected.add(char(octet)) # Independent complete encoding proves every resumed offset and exact checksum byte.
  assert readFile(journalPath) == expected
  check(held, 7)
  check(next, 8)
  let third = exportTrieChanges(b, c, limits.repository.codec.records).value
  resetIo()
  limitWrites(8)
  armIo(writeIo, 1, 1, failedIo)
  assert file.publish(next, third).error == FileError.IoFailure
  assert pendingIo() == 0 and ioCalls(writeIo) == 2, "permanent partial write must stop immediately"
  assert file.snapshot.error == FileError.RecoveryRequired
  resetIo()
  assert file.close == FileError.None
  assert readFile(journalPath).len == expected.len+8
  if managed:
    # Strict startup cannot repair a tail; only an independently exact complete-prefix token may truncate it.
    assert openManagedFileRepository(file, path, default(StorageChainId), limits) ==
        FileError.InvalidJournal
    assert recoverManagedFileRepository(file, path, default(StorageChainId), limits,
      RepositoryGeneration(1), held.commitment.root) == FileError.RecoveryMismatch
    assert recoverManagedFileRepository(file, path, default(StorageChainId), limits,
      RepositoryGeneration(2), next.commitment.root) == FileError.None
  else:
    assert openFileRepository(file, path, default(StorageChainId), journal) ==
        FileError.InvalidJournal
    assert recoverFileRepository(file, path, default(StorageChainId), journal,
      RepositoryGeneration(1), held.commitment.root) == FileError.RecoveryMismatch
    assert recoverFileRepository(file, path, default(StorageChainId), journal,
      RepositoryGeneration(2), next.commitment.root) == FileError.None
  assert readFile(journalPath) == expected
  assert uint64(file.snapshot.value.generation) == 2
  let resumed = file.publish(file.snapshot.value, third).value
  assert uint64(resumed.generation) == 3
  check(resumed, 10)
  assert file.close == FileError.None and source.close == RepositoryError.None
  check(held, 7)
  check(next, 8)
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)]) # Only the test's exact epoch may be retired.
  else:
    assert posix.unlink(path.toCString()) == 0
try:
  scenario(false)
  scenario(true)
except:
  quit(2)
echo "PASS storage interrupted writes: genuine short progress, exact retries, permanent refusal and trusted repair"
