# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed journal leases keep the stable lock alive across append, manifest replacement and descriptor transfer.
# @@Verification={"arc":"storage_managed_publication_io_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import std/posix/posix
import ../../../src/storage/[managed_io, managed_manifest, file_errors]
import ../../../src/codec/bounded
proc cycle(directory: ManagedDirectory) =
  ## A complete journal lease and detached read buffer retire before the next isolated iteration.
  var journal = default(ManagedJournal)
  let loaded = openManagedJournal(journal, directory, ManagedEpoch(1), ByteLimit(4))
  assert loaded.error == FileError.None and loaded.value.len == 4
  assert journal.close == FileError.None
proc main() {.raises.} =
  ## Atomic manifest replacement and append ownership retain exact bytes and refuse parent retirement.
  var path = "storage-managed-publication"
  var directory = default(ManagedDirectory)
  var competitor = default(ManagedDirectory)
  var journal = default(ManagedJournal)
  var moved = default(ManagedJournal)
  defer:
    if moved.opened: discard moved.close
    if journal.opened: discard journal.close
    if competitor.opened: discard competitor.close
    if directory.opened: discard directory.close
  assert initializeManagedDirectory(directory, path) == FileError.None
  assert createManagedFile(directory, ManagedFileKind.Journal, ManagedEpoch(1), [1'u8, 2],
      ByteLimit(4)) == FileError.None
  assert openManagedJournal(journal, directory, ManagedEpoch(1), ByteLimit(4)).value == @[1'u8, 2]
  assert directory.close == FileError.Busy
  assert appendManagedJournal(journal, [3'u8, 4]) == FileError.None
  assert appendManagedJournal(journal, [5'u8]) == FileError.LimitExceeded
  assert managedJournalBytes(journal).value == 4
  assert replaceManagedManifest(directory, [7'u8], ByteLimit(1)) == FileError.None
  assert openManagedDirectory(competitor, path) == FileError.Busy
  assert replaceManagedManifest(directory, [8'u8, 9], ByteLimit(2)) == FileError.None
  assert readManagedFile(directory, ManagedFileKind.Current, ManagedEpoch(0), ByteLimit(2)).value ==
      @[8'u8, 9]
  assert discardManagedPending(directory) == FileError.None
  assert moveManagedJournal(moved, journal) == FileError.None
  assert not journal.opened and moved.opened
  assert directory.close == FileError.Busy
  assert moved.close == FileError.None
  assert openManagedJournal(journal, directory, ManagedEpoch(1), ByteLimit(4)).value == @[1'u8, 2, 3, 4]
  assert journal.close == FileError.None
  for iteration in 0..<25: cycle(directory) # Warm fixed filename and detached read allocation paths.
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(directory) # Every journal state lease must release exactly once.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_managed_publication_io", 1000, before, after)
  assert removeManagedFile(directory, ManagedFileKind.Journal, ManagedEpoch(1)) == FileError.None
  assert directory.close == FileError.None
  assert openManagedDirectory(competitor, path) == FileError.None
  assert competitor.close == FileError.None
  var current = path & "/CURRENT"
  var lockPath = path & "/LOCK"
  assert posix.unlink(current.toCString()) == 0
  assert posix.unlink(lockPath.toCString()) == 0
  assert posix.rmdir(path.toCString()) == 0
try:
  main()
except:
  quit(2)
echo "PASS storage managed publication IO: journal leases, exact append, atomic CURRENT and retirement"
