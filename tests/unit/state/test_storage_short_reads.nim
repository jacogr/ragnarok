# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Interrupted genuine short reads preserve exact bytes, typed ceilings and strict refusal semantics.
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
proc scenario(managed: bool) {.raises.} =
  ## Both layouts resume after eight real bytes, refuse permanent error and detect one-byte over-budget input.
  resetIo()
  var path = "storage-short-read-" & $managed & "-" & $int(storageProcessId())
  var limits = managedStorageLimits()
  var journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes)
  let a = storageTrie(7)
  var source = newNodeRepository(limits.repository)
  let seed = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(seed, [seed.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  defer:
    resetIo() # Limits and pending errors belong only to the currently observed strict open.
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
  let original = readFile(journalPath)
  assert file.close == FileError.None
  for failures in [0, 2, 1]:
    resetIo()
    limitReads(8)
    armIo(readIo, 1, cint(failures), if failures == 1: failedIo else: interruptedIo)
    let opened = if managed:
      openManagedFileRepository(file, path, default(StorageChainId), limits)
    else:
      openFileRepository(file, path, default(StorageChainId), journal)
    assert pendingIo() == 0
    if failures == 1:
      assert opened == FileError.IoFailure and not file.opened and ioCalls(readIo) == 2
    else:
      assert opened == FileError.None and ioCalls(readIo) > 3
      let entries = restoreStateEntries(file.snapshot.value, held.commitment.root,
          limits.repository.codec.trie).value
      assert entries.len == 2 and entries[0].value == @[7'u8] and entries[1].value == @[9'u8]
      assert file.close == FileError.None
    resetIo()
    assert readFile(journalPath) == original
  resetIo()
  limitReads(8)
  if managed:
    limits.snapshotBytes = ByteLimit(uint64(readFile(path &
        "/snapshot-0000000000000001.bin").len)-1)
    assert openManagedFileRepository(file, path, default(StorageChainId), limits) ==
        FileError.LimitExceeded
  else:
    journal.bytes = ByteLimit(uint64(original.len)-1)
    assert openFileRepository(file, path, default(StorageChainId), journal) ==
        FileError.LimitExceeded
  assert not file.opened
  if managed:
    assert ioCalls(readIo) > 1 # CURRENT was read before the oversized selected snapshot was refused.
  else:
    assert ioCalls(readIo) == 0 # A known oversized journal must refuse before the first payload read.
  resetIo()
  assert readFile(journalPath) == original
  limits = managedStorageLimits()
  journal.bytes = limits.journalBytes
  if managed:
    assert openManagedFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  else:
    assert openFileRepository(file, path, default(StorageChainId), journal) == FileError.None
  assert uint64(file.snapshot.value.generation) == 1
  assert file.close == FileError.None and source.close == RepositoryError.None
  if managed:
    removeManagedSample(path, [ManagedEpoch(1)])
  else:
    assert posix.unlink(path.toCString()) == 0
try:
  scenario(false)
  scenario(true)
except:
  quit(2)
echo "PASS storage short reads: real eight-byte progress, resumed EINTR, permanent refusal and one-byte ceilings"
