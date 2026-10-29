# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real managed reopen validates selected snapshot/journal identity and every retained complete root.
# @@Verification={"arc":"storage_managed_repository_arc_release"}
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[storage_samples, arc_evidence]
import ../../../src/storage/managed/[repository as managed_repository, manifest as managed_manifest,
    io as managed_io]
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/database_identity
import ../../../src/storage/file/errors as file_errors
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
proc cycle(path: string, limits: ManagedLimits) =
  ## Repeated reopen must release all native and immutable graph owners.
  var repository = default(ManagedRepository)
  assert openManagedRepository(repository, path, default(StorageChainId), limits,
    StorageSchema.FullStateV1) == FileError.None
  assert uint64(repository.snapshot.value.generation) == 2
  assert repository.close == FileError.None
proc main() {.raises.} =
  ## Preserve generation/context/history across restart and refuse a different selected chain or schema.
  let policy = storageLimits()
  let limits = ManagedLimits(repository: policy, roots: ElementLimit(2),
    snapshotBytes: ByteLimit(1000000), journalBytes: ByteLimit(1000000), contextBytes: ByteLimit(8))
  var memory = newNodeRepository(policy)
  let first = storageTrie(7)
  let second = storageTrie(8)
  let old = memory.publish(memory.snapshot.value, exportFullTrie(first,
      policy.codec.records).value).value
  let head = memory.publish(old, exportTrieChanges(first, second, policy.codec.records).value).value
  let selection = selectRepositoryRoots(head, [old.commitment.root, head.commitment.root],
      limits.roots).value
  var repository = default(ManagedRepository)
  var other = default(ManagedRepository)
  defer:
    if other.opened: discard other.close
    if repository.opened: discard repository.close
  let path = "storage-managed-repository"
  assert initializeManagedRepository(repository, path, default(StorageChainId), selection,
    [1'u8, 2], limits, StorageSchema.FullStateV1) == FileError.None
  assert openManagedRepository(other, path, default(StorageChainId), limits,
    StorageSchema.FullStateV1) == FileError.Busy
  let retained = repository.snapshot.value
  var detached = repository.snapshotContext.value
  detached[0] = 99
  assert repository.snapshotContext.value == @[1'u8, 2]
  assert repository.close == FileError.None
  assert restoreHistoricalStateEntries(retained, old.commitment.root,
      policy.codec.trie).value.len == 2
  var wrong = default(array[32, byte])
  wrong[0] = 1
  assert openManagedRepository(repository, path, StorageChainId(wrong), limits,
    StorageSchema.FullStateV1) == FileError.WrongIdentity
  assert not repository.opened
  assert openManagedRepository(repository, path, default(StorageChainId), limits) ==
      FileError.WrongIdentity
  for iteration in 0..<10: cycle(path, limits) # Warm admission and native descriptor allocation paths.
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(path, limits)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_managed_repository", 1000, before, after)
  var directory = default(ManagedDirectory)
  assert openManagedDirectory(directory, path) == FileError.None
  assert removeManagedFile(directory, ManagedFileKind.Snapshot, ManagedEpoch(1)) == FileError.None
  assert directory.close == FileError.None
  assert openManagedRepository(repository, path, default(StorageChainId), limits,
    StorageSchema.FullStateV1) != FileError.None # A selected missing snapshot never falls back to journal bytes.
  assert openManagedDirectory(directory, path) == FileError.None
  assert removeManagedFile(directory, ManagedFileKind.Journal, ManagedEpoch(1)) == FileError.None
  assert directory.close == FileError.None
  var current = path & "/CURRENT"
  var lockPath = path & "/LOCK"
  var nativePath = path
  assert posix.unlink(current.toCString()) == 0
  assert posix.unlink(lockPath.toCString()) == 0
  assert posix.rmdir(nativePath.toCString()) == 0
  assert memory.close == RepositoryError.None
try:
  main()
except:
  quit(2)
echo "PASS storage managed repository: exact epoch, retained roots, chain/schema and detached context"
