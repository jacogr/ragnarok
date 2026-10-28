# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Guard synchronization payloads after default/closed memory and file owners, with real live controls.
import std/assertions
import std/cmdline
import std/syncio
import std/posix/posix
import ../support/storage_samples
import ../../src/storage/node_repository as storage_node_repository
import ../../src/storage/file_repository as storage_file_repository
import ../../src/storage/database_identity as storage_database_identity
import ../../src/storage/durability as storage_durability
import ../../src/codec/bounded as codec_bounded
proc main() =
  ## Select runtime origins without exposing or fabricating a successful durability receipt.
  let member = paramStr(1)
  let origin = paramStr(2)
  if member == "memory":
    var repository = newNodeRepository(storageLimits())
    if origin == "failed": discard repository.close # Closed synchronization has no payload.
    let empty = default(RepositoryResult[StorageDurability])
    let selected = if origin == "default": empty else: repository.synchronize
    echo ord(selected.value)
    if repository.opened: discard repository.close
  else:
    # Use the standard runner parent, independent of earlier per-family local checks.
    let path = "build/tests/storage-synchronization-guard.db"
    var nativePath = path
    discard posix.unlink(nativePath.toCString())
    var repository = default(FileRepository)
    assert initializeFileRepository(repository, path, default(StorageChainId),
      JournalLimits(repository: storageLimits(), bytes: ByteLimit(1048576))) == FileError.None
    if origin == "failed": discard repository.close
    let empty = default(FileResult[StorageDurability])
    let selected = if origin == "default": empty else: repository.synchronize
    # Retire descriptors before the deliberately refused payload access.
    if repository.opened: discard repository.close
    assert posix.unlink(nativePath.toCString()) == 0
    echo ord(selected.value)
main()
