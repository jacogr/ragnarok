# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Manifest epochs, snapshot identities and journal pairs remain exact across all byte corruption.
import std/assertions
import std/syncio
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
let chain = default(StorageChainId)
let schema = StorageSchema.FullStateV1
let limit = ByteLimit(ManagedManifestBytes)
let encoded = encodeManagedManifest(chain, schema, ManagedEpoch(3), RepositoryGeneration(17),
    default(StateRoot), default(StorageChecksum), limit).value
let restored = decodeManagedManifest(encoded.bytes, chain, schema, limit).value
assert uint64(restored.epoch) == 3 and uint64(restored.generation) == 17
assert array[32, byte](restored.checksum) == array[32, byte](encoded.checksum)
for size in 0..<encoded.bytes.len:
  assert decodeManagedManifest(encoded.bytes.toOpenArray(0, size-1), chain, schema, limit).error !=
      ManifestError.None # Exact width precedes hash/field access.
for index in 0..<encoded.bytes.len:
  var corrupted = encoded.bytes
  corrupted[index] = corrupted[index] xor 1
  assert decodeManagedManifest(corrupted, chain, schema, limit).error !=
      ManifestError.None # Every selected field participates in integrity.
assert encodeManagedManifest(chain, schema, ManagedEpoch(0), RepositoryGeneration(1), default(
    StateRoot), default(StorageChecksum), limit).error == ManifestError.InvalidFormat
assert encodeManagedManifest(chain, schema, ManagedEpoch(1), RepositoryGeneration(0), default(
    StateRoot), default(StorageChecksum), limit).error == ManifestError.InvalidFormat
assert encodeManagedManifest(chain, schema, ManagedEpoch(1), RepositoryGeneration(1), default(
    StateRoot), default(StorageChecksum), ByteLimit(ManagedManifestBytes-1)).error ==
    ManifestError.LimitExceeded
var other = default(array[32, byte])
other[0] = 1
assert decodeManagedManifest(encoded.bytes, StorageChainId(other), schema, limit).error ==
    ManifestError.WrongIdentity
assert decodeManagedManifest(encoded.bytes, chain, StorageSchema.FullNodesV1, limit).error ==
    ManifestError.WrongIdentity
let header = encodeManagedJournalHeader(encoded.checksum, ByteLimit(
    ManagedJournalHeaderBytes)).value
assert validateManagedJournalHeader(header, restored.checksum) == ManifestError.None
assert validateManagedJournalHeader(header, StorageChecksum(other)) == ManifestError.WrongIdentity
for index in 0..<header.len:
  var corrupted = header
  corrupted[index] = corrupted[index] xor 1
  assert validateManagedJournalHeader(corrupted, restored.checksum) !=
      ManifestError.None # An unrelated journal can never be replayed under the selected snapshot.
var trailing = header
trailing.add(0'u8)
assert validateManagedJournalHeader(trailing, restored.checksum) == ManifestError.InvalidFormat
echo "PASS storage managed manifest: exact epochs, snapshot binding, journal pairing and corruption"
