# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The same transaction scenario runs against memory and real disk through overloaded storage operations.
# @@Verification={"arc": "storage_backend_contract_arc_release"}
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[storage_samples, arc_evidence]
import ../../../src/storage/[file_repository, node_repository, node_records, full_state_trie,
  database_identity, revision_retention, durability]
import ../../../src/codec/[state_trie, bounded]

proc successful[T](outcome: RepositoryResult[T]): bool =
  ## Memory results expose the shared success contract with backend-specific diagnostics intact.
  outcome.error == RepositoryError.None
proc successful[T](outcome: FileResult[T]): bool =
  ## File results preserve explicit IO uncertainty rather than flattening it to a memory error.
  outcome.error == FileError.None
proc refused(outcome: RepositoryResult[RepositoryView], reason: RepositoryError): bool =
  ## Compare logical admission failures selected by the memory backend.
  outcome.error == reason
proc refused(outcome: FileResult[RepositoryView], reason: RepositoryError): bool =
  ## Disk preparation carries the same actual logical failure in its guarded alternative.
  outcome.error == FileError.InvalidBatch and outcome.batchFailure.error == reason

template exercise(repository, durability: untyped): untyped =
  ## Identical operations check roots/values, present-empty/missing, atomic refusal and retained pins.
  block:
    let limits = storageLimits()
    let initial = storageTrie()
    let empty = repository.snapshot
    assert empty.successful and uint64(empty.value.generation) == 0
    let first = repository.publish(empty.value, exportFullTrie(initial, limits.codec.records).value)
    assert first.successful
    var pins = newRevisionRetention(ElementLimit(1))
    let pin = pins.retain(first.value).value
    # Add a present-empty key, change another value and delete the third; all commit atomically.
    let changed = initial.apply([
      TrieWrite(key: storageKey(0), kind: TrieWriteKind.Put, value: @[8'u8]),
      TrieWrite(key: storageKey(64), kind: TrieWriteKind.Put),
      TrieWrite(key: storageKey(128), kind: TrieWriteKind.Delete)]).value
    let delta = exportTrieChanges(initial, changed, limits.codec.records).value
    let next = repository.publish(first.value, delta)
    assert next.successful and uint64(next.value.generation) == 2
    assert refused(publish(repository, first.value, delta), RepositoryError.StaleView)
    let restored: FullStateTrie = restoreFullTrie(next.value, changed.commitment.root,
      FullStateTrieLimits(trie: limits.codec.trie)).value
    assert restored.lookup(storageKey(0)).value.bytes == @[8'u8]
    assert restored.lookup(storageKey(64)).value.byteLength == 0
    assert restored.lookup(storageKey(128)).error == TrieError.MissingKey
    var invalid = exportTrieChanges(changed, changed, limits.codec.records).value
    invalid.entries = 1
    assert refused(publish(repository, next.value, invalid), RepositoryError.InvalidGraph)
    let current: RepositoryView = snapshot(repository).value
    assert uint64(current.generation) == 2
    assert array[32, byte](current.commitment.root) ==
      array[32, byte](changed.commitment.root)
    let synced = repository.synchronize
    assert synced.successful and synced.value == durability
    let retained: FullStateTrie = restoreFullTrie(lookup(pins, pin).value, initial.commitment.root,
      FullStateTrieLimits(trie: limits.codec.trie)).value
    assert retained.lookup(storageKey(0)).value.bytes == @[7'u8]
    assert pins.release(pin) == RetentionError.None and pins.close == RetentionError.None
    next.value

proc cycle() =
  ## Independent backend owners agree but their view identities cannot authorize each other's writes.
  let path = "storage-backend-contract.db"
  let limits = JournalLimits(repository: storageLimits(), bytes: ByteLimit(1048576))
  var memory = newNodeRepository(limits.repository)
  var file = default(FileRepository)
  assert initializeFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  let fromMemory = exercise(memory, StorageDurability.ProcessLifetime)
  let fromFile = exercise(file, StorageDurability.FileAndDirectorySynced)
  assert array[32, byte](fromMemory.commitment.root) == array[32, byte](fromFile.commitment.root)
  assert fromMemory.commitment.entries == fromFile.commitment.entries
  assert fromMemory.commitment.nodes == fromFile.commitment.nodes
  assert fromMemory.storedNodes == fromFile.storedNodes
  # Equal scalar metadata never makes unrelated repository views interchangeable for mutation.
  let unchanged = TrieExport(base: fromFile.commitment.root, root: fromFile.commitment.root,
    entries: uint64(fromFile.commitment.entries), nodes: uint64(fromFile.commitment.nodes))
  assert file.publish(fromMemory, unchanged).refused(RepositoryError.StaleView)
  assert memory.publish(fromFile, unchanged).refused(RepositoryError.StaleView)
  assert memory.close == RepositoryError.None and file.close == FileError.None
  assert memory.synchronize.error == RepositoryError.Uninitialized
  assert file.synchronize.error == FileError.Uninitialized
  assert openFileRepository(file, path, default(StorageChainId), limits) == FileError.None
  assert file.publish(fromFile, unchanged).refused(RepositoryError.StaleView)
  let reopened = file.snapshot.value
  assert uint64(reopened.generation) == 2
  assert array[32, byte](reopened.commitment.root) == array[32, byte](fromMemory.commitment.root)
  assert file.synchronize.value == StorageDurability.FileAndDirectorySynced
  assert file.close == FileError.None
  # Detached retained readers still own all values after both native owners have closed.
  let restored = reopened.restoreFullTrie(fromMemory.commitment.root,
    FullStateTrieLimits(trie: limits.repository.codec.trie)).value
  assert restored.lookup(storageKey(64)).value.bytes.len == 0
  var nativePath = path
  assert posix.unlink(nativePath.toCString()) == 0

assert default(StorageDurability) == StorageDurability.Uninitialized
var absentMemory = default(NodeRepository)
var absentFile = default(FileRepository)
assert absentMemory.synchronize.error == RepositoryError.Uninitialized
assert absentFile.synchronize.error == FileError.Uninitialized
for i in 0..<5: cycle() # Warm the exact shared scenario, fsync and retained release paths.
let before = getOccupiedMem()
for i in 0..<1000: cycle() # Both complete owners and every detached revision retire each cycle.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_backend_contract", 1000, before, after)
echo "PASS storage backend contract: identical transactions, explicit durability, owner identity, reopen and ARC"
