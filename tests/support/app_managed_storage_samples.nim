# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored managed-database policies and explicit test-owned namespace retirement helpers.
import std/assertions
import std/posix/posix
import ./storage_samples
import ../../src/storage/managed_repository as storage_managed_repository
import ../../src/storage/managed_manifest as storage_managed_manifest
import ../../src/storage/managed_io as storage_managed_io
import ../../src/storage/file_errors as storage_file_errors
import ../../src/codec/bounded as codec_bounded
proc managedStorageLimits*(): ManagedLimits =
  ## Keep physical budgets generous while preserving the ordinary complete graph ceilings.
  ManagedLimits(repository: storageLimits(), roots: ElementLimit(9), snapshotBytes: ByteLimit(1000000),
    journalBytes: ByteLimit(1000000), contextBytes: ByteLimit(64))
proc removeManagedSample*(path: string, epochs: openArray[ManagedEpoch]) =
  ## Tests own these exact epochs; production never scans/removes an untrusted directory inventory.
  var directory = default(ManagedDirectory)
  assert openManagedDirectory(directory, path) == FileError.None
  for epoch in epochs:
    assert removeManagedFile(directory, ManagedFileKind.Snapshot, epoch) == FileError.None
    assert removeManagedFile(directory, ManagedFileKind.Journal, epoch) == FileError.None
  assert discardManagedPending(directory) == FileError.None
  assert directory.close == FileError.None
  var current = path & "/CURRENT"
  var lockPath = path & "/LOCK"
  var nativePath = path
  assert posix.unlink(current.toCString()) == 0
  assert posix.unlink(lockPath.toCString()) == 0
  assert posix.rmdir(nativePath.toCString()) == 0
