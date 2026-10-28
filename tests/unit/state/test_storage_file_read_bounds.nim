# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Chunked physical loads preserve exact byte ceilings and one-byte overrun detection on real files.
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/storage_samples
import ../../support/app_managed_storage_samples
import ../../../src/storage/managed_io as storage_managed_io
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
proc raw() =
  ## Low-level managed reads cover empty/exact/excess limits around both4096-byte chunk boundaries.
  var path = "storage-read-bounds-managed"
  var directory = default(ManagedDirectory)
  assert initializeManagedDirectory(directory, path) == FileError.None
  defer:
    if directory.opened: discard directory.close # Refused reads must not strand the directory lease.
  var bytes = newSeq[byte](8193)
  for index in 0..<bytes.len:
    bytes[index] = byte(index and 255) # Every chunk and final byte has independently authored content.
  assert createManagedFile(directory, ManagedFileKind.Snapshot, ManagedEpoch(1), bytes,
    ByteLimit(bytes.len)) == FileError.None
  for maximum in [0'u64, 1, 4095, 4096, 4097, 8192, 8193, 8194, high(uint64)]:
    let loaded = readManagedFile(directory, ManagedFileKind.Snapshot, ManagedEpoch(1), ByteLimit(maximum))
    if maximum < uint64(bytes.len):
      assert loaded.error == FileError.LimitExceeded # One excess byte must not become silent truncation.
    else:
      assert loaded.error == FileError.None and loaded.value == bytes
  var detached = readManagedFile(directory, ManagedFileKind.Snapshot, ManagedEpoch(1), ByteLimit(8193)).value
  detached[0] = 99
  assert readManagedFile(directory, ManagedFileKind.Snapshot, ManagedEpoch(1), ByteLimit(
      8193)).value == bytes
  assert removeManagedFile(directory, ManagedFileKind.Snapshot, ManagedEpoch(1)) == FileError.None
  assert directory.close == FileError.None
  var lock = path & "/LOCK"
  assert posix.unlink(lock.toCString()) == 0 and posix.rmdir(path.toCString()) == 0
proc journal() {.raises.} =
  ## A complete real journal crossing two chunks must reopen only under a sufficient physical byte ceiling.
  var path = "storage-read-bounds-journal"
  let limits = managedStorageLimits()
  let policy = FullStateTrieLimits(trie: limits.repository.codec.trie, writes: ElementLimit(1),
    writeValueBytes: ByteLimit(64))
  var payload = newSeq[byte](64)
  var trie = newFullStateTrie([StateEntry(key: storageKey(0), value: payload),
    StateEntry(key: storageKey(128))], policy).value
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes)
  var file = default(FileRepository)
  defer:
    if file.opened: discard file.close # Every failed strict open releases its exact descriptors.
  assert initializeFileRepository(file, path, default(StorageChainId), journal) == FileError.None
  discard file.publish(file.snapshot.value, exportFullTrie(trie,
      limits.repository.codec.records).value).value
  for index in 1..24:
    payload[0] = byte(index) # Each long-value update adds a distinct leaf/branch frame.
    let next = trie.apply([TrieWrite(key: storageKey(0), kind: TrieWriteKind.Put,
        value: payload)]).value
    discard file.publish(file.snapshot.value, exportTrieChanges(trie, next,
        limits.repository.codec.records).value).value
    trie = next
  assert file.close == FileError.None
  let original = readFile(path)
  assert original.len > 8192
  var exact = journal
  exact.bytes = ByteLimit(original.len-1)
  assert openFileRepository(file, path, default(StorageChainId), exact) == FileError.LimitExceeded
  assert not file.opened and readFile(path) == original
  exact.bytes = ByteLimit(original.len)
  assert openFileRepository(file, path, default(StorageChainId), exact) == FileError.None
  let held = file.snapshot.value
  let entries = restoreStateEntries(held, trie.commitment.root, limits.repository.codec.trie).value
  assert entries.len == 2 and entries[0].value == payload and entries[1].value.len == 0
  assert file.close == FileError.None and readFile(path) == original
  assert posix.unlink(path.toCString()) == 0
try:
  raw()
  journal()
except:
  quit(2)
echo "PASS storage file read bounds: chunk boundaries, exact ceilings, excess-byte refusal and detached bytes"
