# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Every initialization barrier preserves forensic bytes and grants ownership only after confirmation.
import std/[assertions, syncio]
import std/posix/posix
import ./[storage_samples, managed_storage_samples, storage_io]
import ../../src/storage/[full_state_trie, node_repository, node_records, file_repository,
  managed_repository, database_identity]
import ../../src/codec/bounded
proc accessNative(path: cstring, mode: cint): cint {.importc: "access", cdecl,
    header: "<unistd.h>".}
  ## Test-only namespace presence uses the SDK; production admission still validates held regular files.
proc sampleExists*(path: string): bool =
  ## Distinguish absent partial-bootstrap files without treating them as storage authority.
  var nativePath = path
  accessNative(nativePath.toCString(), 0) == 0
proc removeBootstrapSample*(path: string, managed: bool) =
  ## Delete only the exact test-owned bootstrap names after all native owners are retired.
  if managed:
    for name in ["CURRENT", "CURRENT.next", "snapshot-0000000000000001.bin",
        "journal-0000000000000001.wal", "LOCK"]:
      var child = path & "/" & name
      if sampleExists(child): assert posix.unlink(child.toCString()) == 0
    var directory = path
    assert posix.rmdir(directory.toCString()) == 0
  else:
    var journal = path
    assert posix.unlink(journal.toCString()) == 0
proc bootstrapCase*(label: string, managed: bool, skip, failures: cint,
    permanent = false): uint64 {.raises.} =
  ## Observe actual barriers from the first exclusive creation through final manifest confirmation.
  resetIo()
  let path = label & "-" & $managed & "-" & $skip & "-" & $int(storageProcessId())
  let limits = managedStorageLimits()
  let journal = JournalLimits(repository: limits.repository, bytes: limits.journalBytes)
  let a = storageTrie(7)
  var source = newNodeRepository(limits.repository)
  let seed = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(seed, [seed.commitment.root], ElementLimit(1)).value
  var file = default(FileRepository)
  defer:
    resetIo() # Never carry an interrupted or refused barrier into test-owned retirement.
    if file.opened: discard file.close
  armIo(syncIo, skip, failures, if permanent: failedIo else: interruptedIo)
  let outcome = if managed:
    initializeManagedFileRepository(file, path, default(StorageChainId), selection, [], limits)
  else:
    initializeFileRepository(file, path, default(StorageChainId), journal)
  result = ioCalls(syncIo)
  assert pendingIo() == 0
  resetIo()
  if permanent:
    assert outcome in [FileError.IoFailure, FileError.PublishedUnsynced] and not file.opened
    assert file.snapshot.error == FileError.Uninitialized
  else:
    assert outcome == FileError.None and file.opened
    assert file.close == FileError.None
  var names: seq[string] = @[]
  if managed:
    for name in ["CURRENT", "CURRENT.next", "snapshot-0000000000000001.bin",
        "journal-0000000000000001.wal", "LOCK"]:
      names.add(path & "/" & name)
  else:
    names.add(path)
  var present: seq[bool] = @[]
  var before: seq[string] = @[]
  for name in names:
    let exists = sampleExists(name)
    present.add(exists)
    before.add(if exists: readFile(name) else: "")
  let retry = if managed:
    initializeManagedFileRepository(file, path, default(StorageChainId), selection, [], limits)
  else:
    initializeFileRepository(file, path, default(StorageChainId), journal)
  assert retry == FileError.AlreadyExists and not file.opened
  let visible = if managed: sampleExists(path & "/CURRENT") else: true
  let reopened = if managed:
    openManagedFileRepository(file, path, default(StorageChainId), limits)
  else:
    openFileRepository(file, path, default(StorageChainId), journal)
  if visible:
    assert reopened == FileError.None and file.opened
    assert uint64(file.snapshot.value.generation) == (if managed: 1'u64 else: 0'u64)
    if managed:
      let entries = restoreStateEntries(file.snapshot.value, seed.commitment.root,
          limits.repository.codec.trie).value
      assert entries.len == 2 and entries[0].value == @[7'u8] and entries[1].value == @[9'u8]
    assert file.close == FileError.None
  else:
    assert reopened != FileError.None and not file.opened
  for index, name in names:
    assert sampleExists(name) == present[index]
    if present[index]: assert readFile(name) == before[index]
  assert source.close == RepositoryError.None
  removeBootstrapSample(path, managed)
