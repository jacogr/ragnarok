# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real descriptor reuse witnesses one-shot ownership retirement even when close reports EINTR.
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
proc scenario(managed: bool, skip: cint) {.raises.} =
  ## Every repository-owned descriptor is retired once; a reused number belongs to another resource.
  resetIo()
  var path = "storage-close-" & $managed & "-" & $skip & "-" & $int(storageProcessId())
  let limits = managedStorageLimits()
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes)
  let a = storageTrie(7)
  var source = newNodeRepository(limits.repository)
  let seed = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(seed, [seed.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  defer:
    resetIo() # Release the independently owned replacement before any further fixture descriptors.
    if file.opened: discard file.close
  if managed:
    assert initializeManagedFileRepository(file, path, default(StorageChainId), selection, [],
        limits) == FileError.None
  else:
    assert initializeFileRepository(file, path, default(StorageChainId), journal) == FileError.None
    discard file.publish(file.snapshot.value, exportFullTrie(a,
        limits.repository.codec.records).value).value
  let held = file.snapshot.value
  let journalPath = if managed: path & "/journal-0000000000000001.wal" else: path
  let bytes = readFile(journalPath)
  resetIo()
  reuseClosedDescriptor()
  armIo(closeIo, skip, 1, interruptedIo)
  assert file.close == FileError.IoFailure and not file.opened
  assert pendingIo() == 0
  let expected = if managed: 3'u64 else: 2'u64
  assert ioCalls(closeIo) == expected
  assert reusedDescriptorOpen() == 1
  assert file.close == FileError.Uninitialized and ioCalls(closeIo) == expected
  assert reusedDescriptorOpen() == 1
  resetIo()
  if managed:
    assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  else:
    assert openFileRepository(file, path, default(StorageChainId), journal) == FileError.None
  assert readFile(journalPath) == bytes
  let entries = restoreStateEntries(file.snapshot.value, held.commitment.root,
      limits.repository.codec.trie).value
  assert entries.len == 2 and entries[0].value == @[7'u8] and entries[1].value == @[9'u8]
  assert file.close == FileError.None and source.close == RepositoryError.None
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)])
  else:
    assert posix.unlink(path.toCString()) == 0
try:
  for skip in 0..1: scenario(false, cint(skip))
  for skip in 0..2: scenario(true, cint(skip))
except:
  quit(2)
echo "PASS storage close reuse: every descriptor retired once, replacement remains live and strict restart succeeds"
