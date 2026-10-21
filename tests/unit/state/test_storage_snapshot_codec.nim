# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed snapshots bind selected generation/root, retained complete graphs and exact context bytes.
import std/[assertions, syncio]
import ../../support/storage_samples
import ../../../src/storage/[node_repository, node_records, full_state_trie, database_identity, snapshot_codec]
import ../../../src/codec/[bounded, state_trie]
let limits = SnapshotLimits(repository: storageLimits(), roots: ElementLimit(2), context: ByteLimit(
    8), bytes: ByteLimit(1000000))
let first = storageTrie(7)
let second = storageTrie(8)
var owner = newNodeRepository(limits.repository)
let old = owner.publish(owner.snapshot.value, exportFullTrie(first,
    limits.repository.codec.records).value).value
let view = owner.publish(old, exportTrieChanges(first, second,
    limits.repository.codec.records).value).value
let selection = selectRepositoryRoots(view, [old.commitment.root, view.commitment.root],
    limits.roots).value
let encoded = encodeRepositorySnapshot(selection, default(StorageChainId),
    StorageSchema.FullStateV1, [1'u8, 2], limits).value
let restored = decodeRepositorySnapshot(encoded.bytes, default(StorageChainId),
    StorageSchema.FullStateV1, limits).value
assert restored.context == @[1'u8, 2] and array[32, byte](restored.checksum) == array[32, byte](
    encoded.checksum)
var repository = restored.repository
assert uint64(repository.snapshot.value.generation) == 2
assert restoreHistoricalStateEntries(repository.snapshot.value, old.commitment.root,
    limits.repository.codec.trie).value.len == 2
assert repository.close == RepositoryError.None
for size in 0..<encoded.bytes.len:
  assert decodeRepositorySnapshot(encoded.bytes.toOpenArray(0, size-1), default(StorageChainId),
      StorageSchema.FullStateV1, limits).error !=
      SnapshotError.None # Every exact extent is required before allocation.
for index in 0..<encoded.bytes.len:
  var changed = encoded.bytes
  changed[index] = changed[index] xor 1
  assert decodeRepositorySnapshot(changed, default(StorageChainId), StorageSchema.FullStateV1,
      limits).error != SnapshotError.None # Metadata and raw node data share one integrity boundary.
var wrongChain = default(array[32, byte])
wrongChain[0] = 1
assert decodeRepositorySnapshot(encoded.bytes, StorageChainId(wrongChain),
    StorageSchema.FullStateV1, limits).error == SnapshotError.WrongIdentity
assert decodeRepositorySnapshot(encoded.bytes, default(StorageChainId), StorageSchema.FullNodesV1,
    limits).error == SnapshotError.WrongIdentity
var exact = limits
exact.bytes = ByteLimit(encoded.bytes.len)
assert encodeRepositorySnapshot(selection, default(StorageChainId), StorageSchema.FullStateV1, [
    1'u8, 2], exact).value.bytes == encoded.bytes
var short = limits
short.context = ByteLimit(1)
assert decodeRepositorySnapshot(encoded.bytes, default(StorageChainId), StorageSchema.FullStateV1,
    short).error == SnapshotError.LimitExceeded
short = limits
short.bytes = ByteLimit(encoded.bytes.len-1)
assert encodeRepositorySnapshot(selection, default(StorageChainId), StorageSchema.FullStateV1, [
    1'u8, 2], short).error != SnapshotError.None
assert decodeRepositorySnapshot(encoded.bytes, default(StorageChainId), StorageSchema.FullStateV1,
    short).error == SnapshotError.LimitExceeded
short = limits
short.repository.codec.trie.items = ElementLimit(1)
assert encodeRepositorySnapshot(selection, default(StorageChainId), StorageSchema.FullStateV1, [],
    short).error == SnapshotError.PolicyMismatch
assert owner.close == RepositoryError.None
assert encodeRepositorySnapshot(selection, default(StorageChainId), StorageSchema.FullStateV1, [],
    limits).error == SnapshotError.None
echo "PASS storage snapshot codec: exact binding, retained roots, all truncations and byte mutations"
