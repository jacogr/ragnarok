# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit managed cleanup removes only validated unselected epochs and never grants staged files authority.
import std/[assertions, syncio]
import ../../support/[storage_samples, managed_storage_samples]
import ../../../src/storage/[managed_repository, managed_manifest, managed_io, node_repository,
  node_records, full_state_trie, database_identity, file_errors]
import ../../../src/codec/bounded
proc main() {.raises.} =
  ## A partial candidate and unrelated epoch survive strict reopen until bounded explicit cleanup.
  let limits = managedStorageLimits()
  var memory = newNodeRepository(limits.repository)
  let trie = storageTrie()
  let initial = memory.publish(memory.snapshot.value, exportFullTrie(trie,
      limits.repository.codec.records).value).value
  let selection = selectRepositoryRoots(initial, [initial.commitment.root], limits.roots).value
  var repository = default(ManagedRepository)
  let path = "storage-managed-staging"
  assert initializeManagedRepository(repository, path, default(StorageChainId), selection,
    [], limits) == FileError.None
  assert repository.close == FileError.None
  var directory = default(ManagedDirectory)
  assert openManagedDirectory(directory, path) == FileError.None
  for epoch in [ManagedEpoch(2), ManagedEpoch(9)]:
    assert createManagedFile(directory, ManagedFileKind.Snapshot, epoch, [99'u8],
        limits.snapshotBytes) == FileError.None
    assert createManagedFile(directory, ManagedFileKind.Journal, epoch, [98'u8],
        limits.journalBytes) == FileError.None
  assert directory.close == FileError.None
  writeFile(path & "/CURRENT.next", "partial")
  assert openManagedRepository(repository, path, default(StorageChainId), limits) == FileError.None
  defer:
    if repository.opened: discard repository.close
  let before = repository.snapshot.value
  assert uint64(before.generation) == 1 and uint64(repository.physicalEpoch.value) == 1
  assert repository.compact(before, [before.commitment.root]).error == FileError.AlreadyExists
  assert repository.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.InvalidRetention
  assert repository.cleanupRetiredEpoch(ManagedEpoch(9)) == FileError.InvalidRetention
  assert repository.discardManagedStaging == FileError.None
  assert repository.discardManagedStaging == FileError.None
  assert repository.compact(before, [before.commitment.root]).value.cleanup == FileError.None
  assert repository.cleanupRetiredEpoch(ManagedEpoch(1)) == FileError.None
  assert repository.cleanupRetiredEpoch(ManagedEpoch(2)) == FileError.InvalidRetention
  assert repository.close == FileError.None
  assert openManagedDirectory(directory, path) == FileError.None
  assert readManagedFile(directory, ManagedFileKind.Snapshot, ManagedEpoch(9), ByteLimit(
      1)).value == @[99'u8]
  assert readManagedFile(directory, ManagedFileKind.Journal, ManagedEpoch(9), ByteLimit(1)).value == @[98'u8]
  assert directory.close == FileError.None
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2), ManagedEpoch(9)])
  assert memory.close == RepositoryError.None
try:
  main()
except:
  quit(2)
echo "PASS storage managed staging: exact bounded cleanup, selected-file refusal and unknown-epoch preservation"
