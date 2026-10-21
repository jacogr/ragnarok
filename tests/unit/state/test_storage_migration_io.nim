# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Destination syscall refusals never change a locked legacy source, retained maps or detached context.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[storage_samples, managed_storage_samples, storage_io, storage_bootstrap_faults]
import ../../../src/storage/[full_state_trie, node_repository, node_records, file_repository,
  managed_repository, file_migration, database_identity]
proc scenario(writeFault: bool, skip, failures: cint, permanent = false): uint64 {.raises.} =
  ## Capture one exact contextual source revision and independently observe every destination boundary.
  resetIo()
  var sourcePath = "storage-migration-source-" & $writeFault & "-" & $skip & "-" & $failures & "-" &
      $permanent & "-" & $int(storageProcessId())
  let path = sourcePath & "-destination"
  let limits = managedStorageLimits()
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes,
      contextBytes: limits.contextBytes)
  let a = storageTrie(7)
  let b = storageTrie(8)
  var source = default(FileRepository)
  var destination = default(FileRepository)
  var competing = default(FileRepository)
  defer:
    resetIo() # Destination failures must not alter source retirement or subsequent independent cases.
    if competing.opened: discard competing.close
    if destination.opened: discard destination.close
    if source.opened: discard source.close
  assert initializeFileRepository(source, sourcePath, default(StorageChainId), journal,
      StorageSchema.FullStateV1) == FileError.None
  let first = source.publish(source.snapshot.value,
      exportFullTrie(a, limits.repository.codec.records).value, [1'u8, 2, 3]).value
  let current = source.publish(first, exportTrieChanges(a, b,
      limits.repository.codec.records).value, [9'u8, 0, 8, 7]).value
  let context = source.snapshotContext.value
  let original = readFile(sourcePath)
  resetIo()
  let operation = if writeFault: writeIo else: syncIo
  armIo(operation, skip, failures, if permanent: failedIo else: interruptedIo)
  let outcome = migrateFileRepository(source, destination, path, default(StorageChainId),
      [first.commitment.root, current.commitment.root], limits)
  result = ioCalls(operation)
  assert pendingIo() == 0
  resetIo()
  if permanent:
    assert outcome in [FileError.IoFailure, FileError.PublishedUnsynced]
    assert not destination.opened and destination.snapshot.error == FileError.Uninitialized
  else:
    assert outcome == FileError.None and destination.opened
    assert destination.close == FileError.None
  assert source.opened and uint64(source.snapshot.value.generation) == 2
  assert source.snapshotContext.value == context and readFile(sourcePath) == original
  assert openFileRepository(competing, sourcePath, default(StorageChainId), journal,
      StorageSchema.FullStateV1) == FileError.Busy
  assert not competing.opened
  assert migrateFileRepository(source, destination, path, default(StorageChainId),
      [first.commitment.root, current.commitment.root], limits) == FileError.AlreadyExists
  assert not destination.opened and readFile(sourcePath) == original
  let visible = sampleExists(path & "/CURRENT")
  let reopened = openManagedFileRepository(destination, path, default(StorageChainId), limits,
      StorageSchema.FullStateV1)
  if visible:
    assert reopened == FileError.None and uint64(destination.snapshot.value.generation) == 2
    assert destination.snapshotContext.value == context
    assert restoreStateEntries(destination.snapshot.value, first.commitment.root,
        limits.repository.codec.trie).error != RepositoryError.None
    for root in [first.commitment.root, current.commitment.root]:
      let entries = restoreHistoricalStateEntries(destination.snapshot.value, root,
          limits.repository.codec.trie).value
      let expected = if array[32, byte](root) == array[32, byte](
          first.commitment.root): 7'u8 else: 8'u8
      assert entries.len == 2 and entries[0].value == @[expected] and entries[1].value == @[9'u8]
    assert destination.close == FileError.None
  else:
    assert reopened != FileError.None and not destination.opened
  assert restoreStateEntries(source.snapshot.value, first.commitment.root,
      limits.repository.codec.trie).error != RepositoryError.None
  for root in [first.commitment.root, current.commitment.root]:
    let entries = restoreHistoricalStateEntries(source.snapshot.value, root,
        limits.repository.codec.trie).value
    let expected = if array[32, byte](root) == array[32, byte](
        first.commitment.root): 7'u8 else: 8'u8
    assert entries.len == 2 and entries[0].value == @[expected] and entries[1].value == @[9'u8]
  assert readFile(sourcePath) == original and source.snapshotContext.value == context
  assert source.close == FileError.None
  removeBootstrapSample(path, true)
  assert posix.unlink(sourcePath.toCString()) == 0
proc main() {.raises.} =
  ## Bound genuine writes and syncs before independently testing resumed and refused copies.
  for writeFault in [false, true]:
    let count = scenario(writeFault, 0, 0)
    assert count > 0 and count < 32
    for skip in 0..<int(count):
      assert scenario(writeFault, cint(skip), 2) == count+2
      discard scenario(writeFault, cint(skip), 1, true)
try:
  main()
except:
  quit(2)
echo "PASS storage migration IO: every destination boundary, exact locked source, opaque context and historical maps"
