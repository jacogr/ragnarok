# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque selections encode canonical independent bytes without transport copies or repeated integrity calls.
# @@Verification={"arc": "storage_selection_encoding_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_snapshot_samples, storage_root_samples, arc_evidence]
import ../../../src/storage/[node_repository, node_records, record_codec, snapshot_codec, database_identity]
import ../../../src/codec/[state_trie, bounded]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## An unavailable backend cannot affect already-admitted body serialization, but must refuse its new frame checksum.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Distinguish original local integrity from serialization of private immutable admitted records.

proc exercise(source: SnapshotFixture) =
  ## Strict mutable encoding supplies an independent byte oracle; only opaque admitted sources avoid new hashing.
  reset(0)
  var records = exportRepositorySelection(source.selection,
      source.limits.repository.codec.records).value
  let expected = encodeRecordCollection(RecordCollection(records: records),
      source.limits.repository.codec).value
  reset(1)
  var encoded = encodeRepositorySelection(source.selection, source.limits.repository.codec)
  assert encoded.error == RepositoryError.None and calls() == 0
  let beforeTransfer = getOccupiedMem()
  let bytes = encoded.takeValue
  assert encoded.error == RepositoryError.Uninitialized and getOccupiedMem() == beforeTransfer
  assert bytes == expected
  for mode in 0..<4:
    var short = source.limits.repository.codec
    if mode == 0: short.encoded = ByteLimit(expected.len-1) # Exact final extent remains independently binding.
    elif mode == 1: short.records.records = TrieNodeLimit(source.selection.retainedNodes-1)
    elif mode == 2: short.records.valueBytes = ByteLimit(source.selection.retainedValueBytes-1)
    else: short.trie.perValue = ByteLimit(0) # Each nonempty leaf keeps the caller's narrower value ceiling.
    assert encodeRepositorySelection(source.selection, short).error == RepositoryError.LimitExceeded
    assert calls() == 0
  assert encodeRecordCollection(RecordCollection(records: records),
      source.limits.repository.codec).error == RecordError.BackendFailure
  assert calls() == 1 # Mutable transports never gain the opaque source's existing integrity authority.
  reset(1)
  let refused = encodeRepositorySnapshot(source.selection, default(StorageChainId),
    StorageSchema.FullStateV1, [1'u8, 2], source.limits)
  assert refused.error == SnapshotError.BackendFailure and calls() == 1
  reset(0)
  var snapshot = encodeRepositorySnapshot(source.selection, default(StorageChainId),
    StorageSchema.FullStateV1, [1'u8, 2], source.limits)
  assert snapshot.error == SnapshotError.None and calls() == 1 # Exactly one new outer checksum, no node rehash.
  let frame = snapshot.takeValue
  var restored = decodeRepositorySnapshot(frame.bytes, default(StorageChainId),
    StorageSchema.FullStateV1, source.limits).value.repository
  let current = restored.snapshot.value
  assert array[32, byte](current.commitment.root) == array[32, byte](
      source.selection.commitment.root)
  assert current.storedNodes == source.selection.retainedNodes
  assert restored.close == RepositoryError.None
  for index in 0..<records.len:
    if records[index].kind == TrieRecordKind.Leaf:
      records[index].payload[0] = records[index].payload[
          0] xor 255 # Mutating detached records cannot change admitted cells.
  assert encodeRecordCollection(RecordCollection(records: records),
      source.limits.repository.codec).error == RecordError.HashMismatch
  assert encodeRepositorySelection(source.selection, source.limits.repository.codec).value == expected

proc union() =
  ## Empty and disjoint historical roots retain canonical collection order independent of caller root order/duplicates.
  let source = rootFixture(65)
  var roots = newSeq[StateRoot](source.roots.len)
  for index in 0..<roots.len: roots[index] = source.roots[roots.len-1-index]
  let first = roots[0]
  roots.add(first) # Capture the scalar identity before resizing its source sequence.
  let selected = selectRepositoryRoots(source.view, roots, ElementLimit(roots.len)).value
  let raw = exportRepositorySelection(selected, source.limits.codec.records).value
  let expected = encodeRecordCollection(RecordCollection(records: raw), source.limits.codec).value
  reset(1)
  assert encodeRepositorySelection(selected, source.limits.codec).value == expected and calls() == 0
  reset(0)
  let decoded = decodeOrderedRecordCollection(expected, source.limits.codec).value
  assert decoded.records.len == 65
  var empty = newNodeRepository(source.limits)
  let view = empty.publish(empty.snapshot.value, default(TrieExport)).value
  let selection = selectRepositoryRoots(view, [view.commitment.root], ElementLimit(1)).value
  assert empty.close == RepositoryError.None
  assert encodeRepositorySelection(selection, source.limits.codec).value ==
    encodeRecordCollection(default(RecordCollection), source.limits.codec).value

proc largeBody() =
  ## The completed owned body retains no detached descriptors, payload graph, source view or duplicate wire buffer.
  let source = snapshotFixture(4096, 256)
  let before = getOccupiedMem()
  block:
    var encoded = encodeRepositorySelection(source.selection, source.limits.repository.codec)
    let bytes = encoded.takeValue
    let retained = getOccupiedMem()-before
    assert retained > 0 and retained <= bytes.len+bytes.len div 8+4096
    assert bytes.len == measureRepositorySelection(source.selection,
        source.limits.repository.codec).value
  assert getOccupiedMem() == before

let policy = snapshotPolicy()
let uninitialized = encodeRepositorySelection(default(RepositorySelection), policy.repository.codec)
assert uninitialized.error == RepositoryError.Uninitialized
exercise(snapshotFixture(2, 1)) # Warm provider/report-free ownership paths before exact release observations.
largeBody()
union()
for warmup in 0..<10: exercise(snapshotFixture(2, 1))
let before = getOccupiedMem()
for iteration in 0..<1000: exercise(snapshotFixture(2, 1))
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_selection_encoding", 1000, before, after)
echo "PASS storage selection encoding: canonical opaque bodies, one checksum, strict raw validation and ARC"
