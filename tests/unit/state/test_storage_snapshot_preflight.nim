# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Declared complete-map snapshot limits refuse before outer hashing, with genuine integrity controls.
import std/[assertions, syncio]
import ../../support/storage_samples
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/[snapshot_codec, database_identity]
import ../../../src/codec/bounded
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset actual primitive counters without substituting hash results.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe whether header quota refusal reaches any integrity operation.
proc put(bytes: var seq[byte], offset: int, value: uint64) =
  ## Authored little-endian header fields deliberately leave the outer checksum invalid.
  for index in 0..<8:
    bytes[offset+index] = byte((value shr (8*index)) and 255)
let policy = SnapshotLimits(repository: storageLimits(), roots: ElementLimit(2),
  context: ByteLimit(8), bytes: ByteLimit(1000000))
var source = newNodeRepository(policy.repository)
let view = source.publish(source.snapshot.value, exportFullTrie(storageTrie(),
  policy.repository.codec.records).value).value
let selected = selectRepositoryRoots(view, [view.commitment.root], policy.roots).value
let encoded = encodeRepositorySnapshot(selected, default(StorageChainId),
  StorageSchema.FullStateV1, [1'u8], policy).value.bytes
const base = "RAGNAROK-SNAPSHOT-V1".len+1
for offset in [base+73, base+81]:
  # Both host-sized and full-width oversized counts must stop before checksum or record hashing.
  for number in [4001'u64, high(uint64)]:
    var oversized = encoded
    put(oversized, offset, number)
    reset(0)
    assert decodeRepositorySnapshot(oversized, default(StorageChainId), StorageSchema.FullStateV1,
      policy).error == SnapshotError.LimitExceeded
    assert int(calls()) == 0
var narrower = policy
narrower.repository.codec.trie.items = ElementLimit(1)
reset(0)
assert decodeRepositorySnapshot(encoded, default(StorageChainId), StorageSchema.FullStateV1,
  narrower).error == SnapshotError.LimitExceeded
assert int(calls()) == 0
narrower = policy
narrower.repository.codec.trie.nodes = typeof(narrower.repository.codec.trie.nodes)(2)
reset(0)
assert decodeRepositorySnapshot(encoded, default(StorageChainId), StorageSchema.FullStateV1,
  narrower).error == SnapshotError.LimitExceeded
assert int(calls()) == 0
var plausible = encoded
put(plausible, base+81, 2)
reset(0)
assert decodeRepositorySnapshot(plausible, default(StorageChainId), StorageSchema.FullStateV1,
  policy).error == SnapshotError.ChecksumMismatch
assert int(calls()) == 1 # Bounded plausible header claims cannot bypass genuine outer integrity.
reset(0)
var restored = decodeRepositorySnapshot(encoded, default(StorageChainId),
  StorageSchema.FullStateV1, policy).value.repository
assert int(calls()) == 4 # Three physical records and the outer snapshot checksum all remain checked.
assert restored.snapshot.value.commitment.entries == 2
assert restored.close == RepositoryError.None and source.close == RepositoryError.None
echo "PASS storage snapshot preflight: zero-hash count limits, genuine checksum and complete positive controls"
