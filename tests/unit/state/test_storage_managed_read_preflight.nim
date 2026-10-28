# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Known oversized regular files must refuse before buffering under a one-MiB test heap.
import std/assertions
import std/syncio
import std/posix/posix
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/storage/managed_io as storage_managed_io
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/codec/bounded as codec_bounded

proc truncateNative(fd: cint, extent: int64): cint {.importc: "ftruncate", cdecl,
    header: "<unistd.h>".}
  ## Sparse fixture construction reserves no large Nim buffer and uses the platform off_t ABI.

proc checkFile(directory: ManagedDirectory, path: string, kind: ManagedFileKind) {.raises.} =
  ## Each canonical managed read path must reject a known sixteen-MiB extent without growing four MiB.
  let epoch = ManagedEpoch(1)
  var filename = path & "/" & managedFileName(kind, epoch).value
  if kind == ManagedFileKind.Current:
    # The production staging API protects CURRENT; create only the isolated test-owned raw file.
    writeFile(filename, "")
  else:
    assert createManagedFile(directory, kind, epoch, [], ByteLimit(0)) == FileError.None
  let fd = posix.open(filename.toCString(), O_RDWR)
  assert fd >= 0
  defer:
    discard posix.close(fd) # The fixture's independent descriptor never transfers to a repository.
  assert truncateNative(fd, 16*1024*1024) == 0
  echo "managed preflight: ", kind
  let read = readManagedFile(directory, kind, epoch, ByteLimit(4*1024*1024))
  assert read.error == FileError.LimitExceeded, "known extent must refuse"
  if kind == ManagedFileKind.Journal:
    var journal = default(ManagedJournal)
    let opened = openManagedJournal(journal, directory, epoch, ByteLimit(4*1024*1024))
    assert opened.error == FileError.LimitExceeded and not journal.opened
  var metadata = default(Stat)
  assert posix.fstat(fd, metadata) == 0 and metadata.st_size == 16*1024*1024, "extent must remain unchanged"
  assert truncateNative(fd, 0) == 0, "fixture shrink must succeed"
  let empty = readManagedFile(directory, kind, epoch, ByteLimit(0))
  assert empty.error == FileError.None and empty.value.len == 0, "empty exact-limit read must succeed"
  if kind == ManagedFileKind.Current:
    # CURRENT is protected by the production reclamation API; remove only this test-owned empty fixture.
    assert posix.unlink(filename.toCString()) == 0
  else:
    assert removeManagedFile(directory, kind, epoch) == FileError.None, "fixture epoch cleanup must succeed"

proc main() {.raises.} =
  ## Retire every refused descriptor, then close and reacquire the exact managed lease.
  var path = "storage-managed-read-preflight"
  var directory = default(ManagedDirectory)
  assert initializeManagedDirectory(directory, path) == FileError.None
  defer:
    if directory.opened: discard directory.close
  for kind in [ManagedFileKind.Snapshot, ManagedFileKind.Current, ManagedFileKind.Journal]:
    checkFile(directory, path, kind)
  assert directory.close == FileError.None
  assert openManagedDirectory(directory, path) == FileError.None
  assert directory.close == FileError.None
  var lock = path & "/LOCK"
  assert posix.unlink(lock.toCString()) == 0
  assert posix.rmdir(path.toCString()) == 0

try:
  main()
except:
  quit(2)
echo "PASS managed read preflight: bounded refusal under one-MiB heap, unchanged extents and lease reuse"
