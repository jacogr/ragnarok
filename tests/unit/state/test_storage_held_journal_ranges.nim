# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded caller-owned windows preserve held-inode identity, exact EOF, observable retirement and allocation independence.
# @@Verification={"arc":"storage_held_journal_ranges_arc_release"}
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[arc_evidence, storage_io]
import ../../../src/storage/[managed_io, managed_manifest, file_errors]
import ../../../src/codec/bounded
proc renameNative(source, target: cstring): cint {.importc: "rename", cdecl, header: "<stdio.h>".}
  ## Test-only equal-byte inode replacement cannot become selected-file authority.
proc seed(directory: var ManagedDirectory, path: string): seq[byte] =
  ## An independently authored multi-window payload crosses 4096-byte native chunk boundaries.
  assert initializeManagedDirectory(directory, path) == FileError.None, "initialize owned range fixture"
  result = newSeq[byte](8193)
  for index in 0..<result.len: result[index] = byte(index mod 251)
  assert createManagedFile(directory, ManagedFileKind.Journal, ManagedEpoch(1), result,
      ByteLimit(8193)) == FileError.None, "create exact payload"
proc retire(path: string) =
  ## Remove only known fixture files after every journal and directory owner closes.
  for suffix in ["/journal-0000000000000001.wal", "/REPLACEMENT", "/LOCK"]:
    var name = path & suffix
    let removed = posix.unlink(name.toCString())
    if removed != 0: assert posix.errno() == ENOENT, "only absent owned fixture names allowed"
  var directory = path
  assert posix.rmdir(directory.toCString()) == 0, "retire exact fixture directory"
proc readCycle(journal: var ManagedJournal, directory: ManagedDirectory) =
  ## Small stack windows and scalar results leave no retained whole-log allocation after returning.
  var bytes = default(array[257, byte])
  let read = readManagedJournalRange(journal, directory, ManagedEpoch(1), 4000, bytes)
  assert read.error == FileError.None and read.value == bytes.len, "read complete independent window"
  for index in 0..<bytes.len: assert bytes[index] == byte((4000+index) mod 251), "exact window payload"
proc normal() {.raises.} =
  ## Validate lazy attachment, random windows, EOF, short/EINTR progress, no aliasing and unchanged allocation baseline.
  let path = "held-range-normal-" & $storageProcessId()
  var directory = default(ManagedDirectory)
  var journal = default(ManagedJournal)
  defer:
    resetIo()
    if journal.opened: discard journal.close
    if directory.opened: discard directory.close
  let expected = seed(directory, path)
  resetIo()
  assert attachManagedJournal(journal, directory, ManagedEpoch(1), ByteLimit(8192)) ==
      FileError.LimitExceeded, "size bound before adoption"
  assert not journal.opened and ioCalls(readIo) == 0 and ioCalls(syncIo) == 0, "oversized attachment reads nothing"
  assert attachManagedJournal(journal, directory, ManagedEpoch(1), ByteLimit(8193)) ==
      FileError.None, "attach exact bound without payload allocation"
  assert ioCalls(readIo) == 0 and ioCalls(syncIo) == 2, "attachment anchors bytes and directory without reading payload"
  assert directory.close == FileError.Busy, "attached journal retains parent lease"
  assert attachManagedJournal(journal, directory, ManagedEpoch(1), ByteLimit(8193)) ==
      FileError.Busy, "one append owner"
  var bytes = default(array[9000, byte])
  resetIo()
  limitReads(7)
  armIo(readIo, 0, 1, interruptedIo)
  let loaded = readManagedJournalRange(journal, directory, ManagedEpoch(1), 0, bytes)
  assert loaded.error == FileError.None and loaded.value == 8193, "short reads and EINTR make real bounded progress"
  assert pendingIo() == 0 and ioCalls(readIo) > 1000, "consume actual short/interrupted read controls"
  resetIo()
  for index in 0..<expected.len: assert bytes[index] == expected[index], "exact payload without padding"
  for index in expected.len..<bytes.len: assert bytes[index] == 0, "unfilled caller suffix remains unchanged"
  bytes[0] = 255
  assert readManagedJournalRange(journal, directory, ManagedEpoch(1), 0, bytes).value == 8193, "caller mutation cannot alias held file"
  assert bytes[0] == expected[0], "re-read restores independent source bytes"
  assert readManagedJournalRange(journal, directory, ManagedEpoch(1), 8192, bytes).value == 1, "one-byte final window"
  assert readManagedJournalRange(journal, directory, ManagedEpoch(1), 8193, bytes).value == 0, "exact EOF"
  var empty = default(array[0, byte])
  assert readManagedJournalRange(journal, directory, ManagedEpoch(1), 0, empty).value == 0, "empty interior window"
  assert readManagedJournalRange(journal, directory, ManagedEpoch(1), 8193, empty).value == 0, "empty EOF window"
  resetIo()
  assert readManagedJournalRange(journal, directory, ManagedEpoch(1), high(uint64), bytes).error ==
      FileError.LimitExceeded, "offset bound precedes narrowing and IO"
  assert ioCalls(readIo) == 0 and ioCalls(closeIo) == 0, "invalid offset performs no selected-file IO"
  assert managedJournalBytes(journal).value == 8193, "pure argument refusal preserves journal authority"
  for index in 0..<10: readCycle(journal, directory)
  let before = getOccupiedMem()
  for index in 0..<1000: readCycle(journal, directory)
  let after = getOccupiedMem()
  assert before == after, "range reads retain no whole-log or predecessor allocation"
  recordArcRelease("storage_held_journal_ranges", 1000, before, after)
  assert appendManagedJournal(journal, [17'u8]) == FileError.LimitExceeded, "inherited byte cap remains exact"
  assert journal.close == FileError.None, "retire exact-cap owner"
  assert attachManagedJournal(journal, directory, ManagedEpoch(1), ByteLimit(8194)) ==
      FileError.None, "fresh owner may inherit a distinct explicit cap"
  readCycle(journal, directory)
  assert appendManagedJournal(journal, [17'u8]) == FileError.None, "append remains at EOF after a middle-window seek"
  assert readManagedJournalRange(journal, directory, ManagedEpoch(1), 8193, bytes).value == 1, "range sees confirmed append extent"
  assert bytes[0] == 17 and managedJournalBytes(journal).value == 8194, "exact appended octet and size"
  assert journal.close == FileError.None and directory.close == FileError.None, "explicit resource retirement"
  retire(path)
proc refused(mode: int) {.raises.} =
  ## Real IO failures and changed selected names/extents poison only the current held owner, never silently pad or restart it.
  let path = "held-range-refused-" & $storageProcessId() & "-" & $mode
  var directory = default(ManagedDirectory)
  var journal = default(ManagedJournal)
  defer:
    resetIo()
    if journal.opened: discard journal.close
    if directory.opened: discard directory.close
  let expected = seed(directory, path)
  assert attachManagedJournal(journal, directory, ManagedEpoch(1), ByteLimit(8194)) == FileError.None
  var filename = path & "/journal-0000000000000001.wal"
  let descriptor = posix.open(filename.toCString(), O_RDWR)
  assert descriptor >= 0, "owned mutation control descriptor"
  defer:
    resetIo()
    discard posix.close(descriptor)
  resetIo()
  if mode == 0:
    armIo(readIo, 0, 1, failedIo) # Actual read refusal must not produce success with a partial caller buffer.
  elif mode == 1:
    assert shrinkOnRead(descriptor, 128) == 0, "arm real post-stat shrink"
  elif mode == 2:
    assert growOnRead(descriptor, 8194) == 0, "arm real post-stat growth"
  elif mode == 3:
    var replacement = path & "/REPLACEMENT"
    assert renameNative(filename.toCString(), replacement.toCString()) == 0, "move held inode out of selected name"
    var text = newString(expected.len)
    for index in 0..<expected.len: text[index] = char(expected[index])
    writeFile(filename, text) # Equal bytes in another inode cannot satisfy the held-name identity contract.
  else:
    armIo(closeIo, 0, 1, failedIo) # Selected-name probe retirement is observable and never retried.
  var bytes = default(array[9000, byte])
  let loaded = readManagedJournalRange(journal, directory, ManagedEpoch(1), 0, bytes)
  let reason = if mode == 0 or mode == 4: FileError.IoFailure else: FileError.RecoveryMismatch
  assert loaded.error == reason, "typed selected-range refusal"
  if mode == 0 or mode == 4: assert pendingIo() == 0, "consume exact IO refusal"
  if mode == 1: assert shrinkPending() == 0, "consume post-stat shrink"
  if mode == 2: assert growthPending() == 0, "consume post-stat growth"
  if mode == 3: assert ioCalls(readIo) == 0, "inode mismatch precedes payload reads"
  resetIo()
  assert managedJournalBytes(journal).error == FileError.RecoveryRequired, "uncertainty poisons fresh observations"
  assert appendManagedJournal(journal, []) == FileError.RecoveryRequired, "uncertainty refuses append"
  assert readManagedJournalRange(journal, directory, ManagedEpoch(1), 0, bytes).error ==
      FileError.RecoveryRequired, "uncertainty refuses range retry"
  assert journal.close == FileError.None and directory.close == FileError.None, "poisoned owners still retire explicitly"
  retire(path)
proc attachRefusal(skip: cint) {.raises.} =
  ## Each attachment durability barrier must fail without adopting a journal lease or preventing explicit retry.
  let path = "held-range-attach-refused-" & $storageProcessId() & "-" & $skip
  var directory = default(ManagedDirectory)
  var journal = default(ManagedJournal)
  defer:
    resetIo()
    if journal.opened: discard journal.close
    if directory.opened: discard directory.close
  discard seed(directory, path)
  resetIo()
  armIo(syncIo, skip, 1, failedIo)
  assert attachManagedJournal(journal, directory, ManagedEpoch(1), ByteLimit(8193)) ==
      FileError.IoFailure, "typed attachment barrier refusal"
  assert pendingIo() == 0 and not journal.opened, "failed attachment adopts no lease"
  resetIo()
  assert directory.close == FileError.None, "failed attachment leaves no journal count"
  assert openManagedDirectory(directory, path) == FileError.None, "fresh explicit directory retry"
  assert attachManagedJournal(journal, directory, ManagedEpoch(1), ByteLimit(8193)) ==
      FileError.None, "fresh attach after refused barrier"
  assert journal.close == FileError.None and directory.close == FileError.None, "retire successful retry"
  retire(path)
proc main() {.raises.} =
  ## Defaults refuse without touching caller storage; coherent normal and refusal groups cover the complete bounded IO contract.
  var directory = default(ManagedDirectory)
  var journal = default(ManagedJournal)
  var bytes = default(array[1, byte])
  assert attachManagedJournal(journal, directory, ManagedEpoch(1), ByteLimit(1)) ==
      FileError.Uninitialized
  assert readManagedJournalRange(journal, directory, ManagedEpoch(1), 0, bytes).error ==
      FileError.Uninitialized
  normal()
  for mode in 0..<5: refused(mode)
  for skip in 0..<2: attachRefusal(cint(skip))
try:
  main()
except:
  quit(2)
echo "PASS held journal ranges: bounded windows, exact inode and EOF, short reads, refusal poison and ARC retirement"
