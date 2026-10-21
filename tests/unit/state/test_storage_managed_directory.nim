# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stable managed directory locks and descriptor-relative files preserve exclusive ownership and exact bytes.
import std/[assertions, syncio]
import std/posix/posix
import ../../../src/storage/[managed_io, managed_manifest, file_repository]
import ../../../src/codec/bounded
proc renamePath(source, destination: cstring): cint {.importc: "rename", cdecl,
    header: "<stdio.h>".}
  ## Exercise held-directory relative IO after an external rename without native production hooks.
proc main() {.raises.} =
  ## Competing owners, overwrite, short reads and refused names leave the selected namespace unchanged.
  var path = "storage-managed-directory"
  var directory = default(ManagedDirectory)
  var competitor = default(ManagedDirectory)
  defer:
    if competitor.opened: discard competitor.close
    if directory.opened: discard directory.close
  assert initializeManagedDirectory(directory, path) == FileError.None
  assert openManagedDirectory(competitor, path) == FileError.Busy
  assert initializeManagedDirectory(competitor, path) == FileError.AlreadyExists
  let epoch = ManagedEpoch(1)
  assert createManagedFile(directory, ManagedFileKind.Snapshot, epoch, [1'u8, 2, 3], ByteLimit(
      3)) == FileError.None
  assert createManagedFile(directory, ManagedFileKind.Snapshot, epoch, [9'u8], ByteLimit(1)) ==
      FileError.AlreadyExists
  assert readManagedFile(directory, ManagedFileKind.Snapshot, epoch, ByteLimit(3)).value == @[1'u8, 2, 3]
  assert readManagedFile(directory, ManagedFileKind.Snapshot, epoch, ByteLimit(2)).error ==
      FileError.LimitExceeded
  assert createManagedFile(directory, ManagedFileKind.Current, epoch, [], ByteLimit(0)) ==
      FileError.InvalidPath
  assert removeManagedFile(directory, ManagedFileKind.Current, epoch) == FileError.InvalidPath
  assert managedFileName(ManagedFileKind.Journal, ManagedEpoch(0)).error == FileError.InvalidPath
  assert managedFileName(ManagedFileKind.Snapshot, ManagedEpoch(high(uint64))).value == "snapshot-ffffffffffffffff.bin"
  var linkPath = path & "-link"
  assert posix.symlink(path.toCString(), linkPath.toCString()) == 0
  assert openManagedDirectory(competitor, linkPath) == FileError.IoFailure
  assert posix.unlink(linkPath.toCString()) == 0
  var targetName = managedFileName(ManagedFileKind.Snapshot, epoch).value
  var aliasPath = path & "/" & managedFileName(ManagedFileKind.Snapshot, ManagedEpoch(2)).value
  assert posix.symlink(targetName.toCString(), aliasPath.toCString()) == 0
  assert readManagedFile(directory, ManagedFileKind.Snapshot, ManagedEpoch(2), ByteLimit(
      3)).error == FileError.IoFailure
  assert removeManagedFile(directory, ManagedFileKind.Snapshot, ManagedEpoch(2)) ==
      FileError.IoFailure
  assert posix.unlink(aliasPath.toCString()) == 0
  assert posix.mkdir(aliasPath.toCString(), Mode(0o700)) == 0
  assert readManagedFile(directory, ManagedFileKind.Snapshot, ManagedEpoch(2), ByteLimit(
      3)).error == FileError.IoFailure
  assert posix.rmdir(aliasPath.toCString()) == 0
  var moved = path & "-moved"
  assert renamePath(path.toCString(), moved.toCString()) == 0
  assert readManagedFile(directory, ManagedFileKind.Snapshot, epoch, ByteLimit(3)).value == @[1'u8, 2, 3]
  assert openManagedDirectory(competitor, moved) == FileError.Busy
  assert renamePath(moved.toCString(), path.toCString()) == 0
  assert directory.close == FileError.None
  assert openManagedDirectory(competitor, path) == FileError.None
  assert readManagedFile(competitor, ManagedFileKind.Snapshot, epoch, ByteLimit(3)).value == @[1'u8, 2, 3]
  assert removeManagedFile(competitor, ManagedFileKind.Snapshot, epoch) == FileError.None
  assert removeManagedFile(competitor, ManagedFileKind.Snapshot, epoch) == FileError.None
  assert competitor.close == FileError.None
  var lockPath = path & "/LOCK"
  assert posix.unlink(lockPath.toCString()) == 0
  assert posix.rmdir(path.toCString()) == 0
try:
  main()
except:
  quit(2) # Native IO failure never becomes a passing lifecycle test.
echo "PASS storage managed directory: stable locks, relative files, bounds and retirement"
