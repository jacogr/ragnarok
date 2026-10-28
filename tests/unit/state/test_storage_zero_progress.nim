# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Zero-progress writes terminate immediately and preserve explicit recovery authority.
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
proc scenario(managed, partial: bool) {.raises.} =
  ## Both backends refuse zero progress immediately, including after actual eight-byte progress.
  resetIo()
  var path = "storage-zero-progress-" & $managed & "-" & $partial
  let limits = managedStorageLimits()
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes)
  let a = storageTrie(7)
  let b = storageTrie(8)
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
  resetIo()
  limitWrites(8)
  assert zeroWrites(cint(if partial: 1 else: 0), 1) == 0
  assert file.publish(held, delta).error == FileError.IoFailure
  assert pendingZeroWrites() == 0 and ioCalls(writeIo) == (if partial: 2'u64 else: 1'u64)
  assert file.snapshot.error == FileError.RecoveryRequired
  resetIo()
  assert file.close == FileError.None
  assert readFile(journalPath).len == original.len+(if partial: 8 else: 0)
  if managed:
    # A real partial prefix cannot become a live map without independently authorized truncation.
    let opened = openManagedFileRepository(file, path, default(StorageChainId), limits)
    assert opened == (if partial: FileError.InvalidJournal else: FileError.None)
    if file.opened: assert file.close == FileError.None
    assert recoverManagedFileRepository(file, path, default(StorageChainId), limits,
      RepositoryGeneration(1), held.commitment.root) == FileError.None
  else:
    let opened = openFileRepository(file, path, default(StorageChainId), journal)
    assert opened == (if partial: FileError.InvalidJournal else: FileError.None)
    if file.opened: assert file.close == FileError.None
    assert recoverFileRepository(file, path, default(StorageChainId), journal,
      RepositoryGeneration(1), held.commitment.root) == FileError.None
  assert readFile(journalPath) == original
  check(file.snapshot.value, 7)
  let resumed = file.publish(file.snapshot.value, delta).value
  check(resumed, 8)
  assert file.close == FileError.None and source.close == RepositoryError.None
  check(held, 7)
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)]) # Only the test's exact epoch may be retired.
  else:
    assert posix.unlink(path.toCString()) == 0
try:
  for managed in [false, true]:
    for partial in [false, true]:
      scenario(managed, partial) # Zero progress terminates before or after genuine partial IO.
except:
  quit(2)
echo "PASS storage zero progress: no spin, poisoned owners, exact bytes and independent partial-tail repair"
