# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real post-stat truncation must return only observed bytes from a preallocated native read buffer.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[storage_io, storage_samples]
import ../../../src/storage/[managed_io, managed_manifest, file_errors, file_repository,
  full_state_trie, node_repository, node_records, database_identity]
import ../../../src/codec/bounded

proc scenario(mode, extent: int) {.raises.} =
  ## The test alone owns the truncation descriptor; each reader still performs genuine short/EINTR IO.
  resetIo()
  var path = "storage-read-shrink-" & $mode & "-" & $extent & "-" & $int(storageProcessId())
  var directory = default(ManagedDirectory)
  assert initializeManagedDirectory(directory, path) == FileError.None
  let kind = if mode == 0: ManagedFileKind.Snapshot
    elif mode == 1: ManagedFileKind.Current
    else: ManagedFileKind.Journal
  let epoch = ManagedEpoch(1)
  var source = newSeq[byte](8193)
  for index in 0..<source.len:
    source[index] = byte(index mod 251) # Distinct values expose padding and misplaced short-read prefixes.
  var filename = path & "/" & managedFileName(kind, epoch).value
  if kind == ManagedFileKind.Current:
    var text = newString(source.len)
    for index in 0..<source.len:
      text[index] = char(source[index]) # Only this exclusive fixture authors a raw CURRENT file.
    writeFile(filename, text)
  else:
    assert createManagedFile(directory, kind, epoch, source, ByteLimit(8193)) == FileError.None
  let owned = posix.open(filename.toCString(), O_RDWR)
  assert owned >= 0
  assert shrinkOnRead(-1, extent) == -1
  assert shrinkOnRead(owned, -1) == -1 and shrinkOnRead(owned, 8193) == -1
  assert shrinkOnRead(owned, extent) == 0 and shrinkPending() == 1
  assert growOnRead(owned, 8194) == -1 and shrinkOnRead(owned, extent) == -1
  limitReads(7)
  armIo(readIo, 0, 1, interruptedIo) # EINTR leaves the one-shot mutation pending until actual IO.
  var expected = newSeq[byte](extent)
  for index in 0..<expected.len:
    expected[index] = source[index]
  if mode == 3:
    var journal = default(ManagedJournal)
    var loaded = openManagedJournal(journal, directory, epoch, ByteLimit(8193))
    assert loaded.error == FileError.None
    assert loaded.takeValue == expected
    assert journal.close == FileError.None
  else:
    var loaded = readManagedFile(directory, kind, epoch, ByteLimit(8193))
    assert loaded.error == FileError.None
    assert loaded.takeValue == expected
  assert shrinkPending() == 0 and pendingIo() == 0 and ioCalls(readIo) > 1
  resetIo()
  var metadata = default(Stat)
  assert posix.fstat(owned, metadata) == 0 and metadata.st_size == extent
  assert posix.close(owned) == 0
  if kind == ManagedFileKind.Current:
    assert posix.unlink(filename.toCString()) == 0
  else:
    assert removeManagedFile(directory, kind, epoch) == FileError.None
  assert directory.close == FileError.None
  var lock = path & "/LOCK"
  assert posix.unlink(lock.toCString()) == 0 and posix.rmdir(path.toCString()) == 0

proc journalScenario(mode: int) {.raises.} =
  ## Strict journal admission sees the real shrunken prefix, without padding or implicit tail repair.
  resetIo()
  var path = "storage-journal-shrink-" & $mode & "-" & $int(storageProcessId())
  let limits = JournalLimits(repository: storageLimits(), bytes: ByteLimit(65536))
  var repository = default(FileRepository)
  assert initializeFileRepository(repository, path, default(StorageChainId), limits) == FileError.None
  let trie = storageTrie(7)
  discard repository.publish(repository.snapshot.value,
    exportFullTrie(trie, limits.repository.codec.records).value).value
  assert repository.close == FileError.None
  let original = readFile(path)
  assert original.len < 65536 and original.len > StorageIdentityBytes
  let extent = case mode
    of 0: 0
    of 1: StorageIdentityBytes-1
    of 2: StorageIdentityBytes
    else: original.len-1
  let readonly = posix.open(path.toCString(), O_RDONLY)
  assert readonly >= 0 and shrinkOnRead(readonly, extent) == -1
  assert posix.close(readonly) == 0 and shrinkPending() == 0
  let owned = posix.open(path.toCString(), O_RDWR)
  assert owned >= 0 and shrinkOnRead(owned, extent) == 0
  limitReads(7)
  let opened = openFileRepository(repository, path, default(StorageChainId), limits)
  assert shrinkPending() == 0
  if mode == 2:
    # A complete identity followed by actual EOF is exactly the empty generation, not a padded frame.
    assert opened == FileError.None and uint64(repository.snapshot.value.generation) == 0
    assert repository.snapshot.value.commitment.entries == 0
    assert repository.close == FileError.None
  else:
    # Partial identity and partial frame remain strict refusals, with no selected owner adopted.
    assert opened == (if mode < 2: FileError.WrongIdentity else: FileError.InvalidJournal)
    assert not repository.opened
  resetIo()
  assert readFile(path) == original[0..<extent]
  assert posix.close(owned) == 0 and posix.unlink(path.toCString()) == 0

try:
  for mode in 0..3:
    for extent in [0, 1, 4095, 4096]:
      scenario(mode, extent) # Empty and chunk-boundary tails must never expose preallocated zero padding.
  for mode in 0..3:
    journalScenario(mode) # Complete and torn physical prefixes exercise the separate append layout.
except:
  quit(2)
echo "PASS storage read shrink: real truncation, exact prefixes and interrupted short progress"
