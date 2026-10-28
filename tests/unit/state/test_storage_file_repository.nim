# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real append/sync/reopen and cooperative ownership preserve retained complete physical views.
# @@Verification={"arc": "storage_file_repository_arc_release"}
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/storage_samples
import ../../support/testing_arc_evidence
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/bounded as codec_bounded

proc cycle() =
  ## Files live inside the native runner's ignored work directory; cleanup follows explicit close.
  let path = "storage-journal-test.db"
  let limits = JournalLimits(repository: storageLimits(), bytes: ByteLimit(1048576))
  let chain = default(StorageChainId)
  var file = default(FileRepository)
  assert initializeFileRepository(file, path, chain, limits) == FileError.None
  let empty = file.snapshot.value
  let initial = storageTrie()
  let first = file.publish(empty, exportFullTrie(initial,
      limits.repository.codec.records).value).value
  let changed = initial.apply([TrieWrite(key: storageKey(0), kind: TrieWriteKind.Put, value: @[8'u8])]).value
  let next = file.publish(first, exportTrieChanges(initial, changed,
      limits.repository.codec.records).value).value
  assert uint64(next.generation) == 2 and next.storedNodes == 5
  var contender = default(FileRepository)
  assert openFileRepository(contender, path, chain, limits) == FileError.Busy
  assert not contender.opened
  assert initializeFileRepository(contender, path, chain, limits) == FileError.AlreadyExists
  let stale = file.publish(first, exportTrieChanges(initial, changed,
      limits.repository.codec.records).value)
  assert stale.error == FileError.InvalidBatch and stale.batchFailure.error ==
      RepositoryError.StaleView
  assert file.close == FileError.None
  assert restoreFullTrie(first, initial.commitment.root, FullStateTrieLimits(
      trie: limits.repository.codec.trie)).value.lookup(storageKey(0)).value.bytes == @[7'u8]
  var other = default(array[32, byte])
  other[0] = 1
  assert openFileRepository(file, path, StorageChainId(other), limits) == FileError.WrongIdentity
  assert not file.opened
  assert openFileRepository(file, path, chain, limits) == FileError.None
  let reopened = file.snapshot.value
  assert uint64(reopened.generation) == 2
  let restored = restoreFullTrie(reopened, changed.commitment.root,
    FullStateTrieLimits(trie: limits.repository.codec.trie)).value
  assert restored.lookup(storageKey(0)).value.bytes == @[8'u8]
  assert file.close == FileError.None
  assert file.snapshot.error == FileError.Uninitialized
  var nativePath = path
  assert posix.unlink(nativePath.toCString()) == 0

for i in 0..<5: cycle() # Warm exact durable publication and lock/read lifecycle paths.
let before = getOccupiedMem()
for i in 0..<1000: cycle() # Real syncs and independently retained views retire on every iteration.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_file_repository", 1000, before, after)
echo "PASS storage file repository: durable deltas, strict reopen, chain/lock/stale refusal and ARC"
