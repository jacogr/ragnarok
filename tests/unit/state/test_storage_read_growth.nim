# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual post-stat growth must still reach bounded read refusal for both physical layouts.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[storage_io, storage_samples]
import ../../../src/storage/[managed_io, managed_manifest, file_repository, database_identity,
  full_state_trie, node_repository, node_records]
import ../../../src/codec/bounded

proc managed(mode: int) {.raises.} =
  ## Snapshot, CURRENT and journal readers see a small stat, then a real one-byte-over-limit growth.
  resetIo()
  var path = "storage-managed-read-growth-" & $mode & "-" & $int(storageProcessId())
  let kind = if mode == 0: ManagedFileKind.Snapshot
    elif mode == 1: ManagedFileKind.Current
    else: ManagedFileKind.Journal
  let epoch = ManagedEpoch(1)
  var directory = default(ManagedDirectory)
  assert initializeManagedDirectory(directory, path) == FileError.None
  var filename = path & "/" & managedFileName(kind, epoch).value
  if kind == ManagedFileKind.Current:
    writeFile(filename, "x") # Only the test authors a raw CURRENT file; production staging remains protected.
  else:
    assert createManagedFile(directory, kind, epoch, [7'u8], ByteLimit(1)) == FileError.None
  let owned = posix.open(filename.toCString(), O_RDWR)
  assert owned >= 0
  defer:
    resetIo() # Forget the borrowed number before its test owner closes it.
    discard posix.close(owned)
    if directory.opened: discard directory.close
  assert growOnRead(-1, 4097) == -1 and growOnRead(owned, 0) == -1
  assert growOnRead(owned, 65537) == -1 and growthPending() == 0
  let readonly = posix.open(filename.toCString(), O_RDONLY)
  assert readonly >= 0 and growOnRead(readonly, 4097) == -1
  assert posix.close(readonly) == 0
  assert growOnRead(owned, 4097) == 0 and growthPending() == 1
  assert growOnRead(owned, 4098) == -1 and growthPending() == 1
  limitReads(8) # Require genuine repeated progress before the final excess byte is refused.
  if mode == 3:
    var journal = default(ManagedJournal)
    let loaded = openManagedJournal(journal, directory, epoch, ByteLimit(4096))
    assert loaded.error == FileError.LimitExceeded and not journal.opened
  else:
    let loaded = readManagedFile(directory, kind, epoch, ByteLimit(4096))
    assert loaded.error == FileError.LimitExceeded
  assert growthPending() == 0 and ioCalls(readIo) > 1
  resetIo()
  var metadata = default(Stat)
  assert posix.fstat(owned, metadata) == 0 and metadata.st_size == 4097
  let bytes = readManagedFile(directory, kind, epoch, ByteLimit(4097)).value
  assert bytes.len == 4097 and bytes[4096] == 0
  assert bytes[0] == (if kind == ManagedFileKind.Current: byte('x') else: 7'u8)
  if kind == ManagedFileKind.Current:
    assert posix.unlink(filename.toCString()) == 0 # Remove only this explicit test fixture.
  else:
    assert removeManagedFile(directory, kind, epoch) == FileError.None
  assert directory.close == FileError.None
  var lock = path & "/LOCK"
  assert posix.unlink(lock.toCString()) == 0 and posix.rmdir(path.toCString()) == 0

proc journal() {.raises.} =
  ## A valid physical journal can grow after its stat; the reader still refuses and never trims it.
  resetIo()
  var path = "storage-journal-read-growth-" & $int(storageProcessId())
  var owner = default(FileRepository)
  let limits = JournalLimits(repository: storageLimits(), bytes: ByteLimit(65536))
  assert initializeFileRepository(owner, path, default(StorageChainId), limits) == FileError.None
  let source = storageTrie()
  discard owner.publish(owner.snapshot.value, exportFullTrie(source,
    limits.repository.codec.records).value).value
  assert owner.close == FileError.None
  let original = readFile(path)
  let ceiling = original.len+32
  assert ceiling < 65536
  let owned = posix.open(path.toCString(), O_RDWR)
  assert owned >= 0
  defer:
    resetIo()
    discard posix.close(owned)
    if owner.opened: discard owner.close
  assert growOnRead(owned, int64(ceiling+1)) == 0
  limitReads(8)
  var short = limits
  short.bytes = ByteLimit(ceiling)
  assert openFileRepository(owner, path, default(StorageChainId), short) == FileError.LimitExceeded
  assert not owner.opened and growthPending() == 0 and ioCalls(readIo) > 1
  resetIo()
  let changed = readFile(path)
  assert changed.len == ceiling+1 and changed[0..<original.len] == original
  # The test alone removes its own deliberate tail, then verifies ordinary exact-head admission.
  assert posix.ftruncate(owned, Off(original.len)) == 0
  assert openFileRepository(owner, path, default(StorageChainId), limits) == FileError.None
  assert uint64(owner.snapshot.value.generation) == 1
  assert owner.close == FileError.None and readFile(path) == original
  assert posix.unlink(path.toCString()) == 0

try:
  for mode in 0..3: managed(mode)
  journal()
except:
  quit(2)
echo "PASS storage read growth: real post-stat writes, excess-byte refusal and preserved fixtures"
