# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque selections encode canonical independent bytes without transport copies or repeated integrity calls.
# @@Verification={"arc": "storage_selection_encoding_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_snapshot_samples, storage_root_samples, arc_evidence]
import ../../../src/storage/node/[repository as node_repository, records as node_records]
import ../../../src/storage/[record_codec, snapshot_codec, database_identity]
import ../../../src/codec/state/trie as state_trie
import ../../../src/codec/bounded

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

proc framing(source: SnapshotFixture) =
  ## Reserved metadata/checksum space never changes canonical bodies or promotes mutable bytes to graph authority.
  let codec = source.limits.repository.codec
  let expected = encodeRepositorySelection(source.selection, codec).value
  reset(1)
  for prefix in [0, 1, 31, 1024]:
    # Odd and empty reservations exercise both boundaries independently of the snapshot's fixed header shape.
    for suffix in [0, 1, 32, 1024]:
      let size = prefix+expected.len+suffix
      var encoded = encodeFramedRepositorySelection(source.selection, codec,
        uint64(prefix), uint64(suffix), ByteLimit(size))
      assert encoded.error == RepositoryError.None and calls() == 0
      var bytes = encoded.takeValue
      assert bytes.len == size and encoded.error == RepositoryError.Uninitialized
      for index in 0..<prefix: assert bytes[index] == 0
      for index in 0..<expected.len: assert bytes[prefix+index] == expected[index]
      for index in prefix+expected.len..<size: assert bytes[index] == 0
      assert encodeFramedRepositorySelection(source.selection, codec, uint64(prefix),
        uint64(suffix), ByteLimit(size-1)).error == RepositoryError.LimitExceeded
      bytes[0] = bytes[0] xor 255 # Detached output mutation cannot affect a later encoding from the admitted owner.
      assert encodeRepositorySelection(source.selection, codec).value == expected
  let before = getOccupiedMem()
  for extent in [uint64(high(int)), uint64(high(int))+1, high(uint64)]:
    # Full-width oversized metadata refuses before narrowing, addition, allocation or any backend call.
    assert encodeFramedRepositorySelection(source.selection, codec, extent, 0,
      ByteLimit(high(uint64))).error == RepositoryError.LimitExceeded
    assert encodeFramedRepositorySelection(source.selection, codec, 0, extent,
      ByteLimit(high(uint64))).error == RepositoryError.LimitExceeded
    assert encodeFramedRepositorySelection(source.selection, codec, extent, extent,
      ByteLimit(high(uint64))).error == RepositoryError.LimitExceeded
  assert calls() == 0 and getOccupiedMem() == before
  var short = codec
  short.encoded = ByteLimit(expected.len-1)
  assert encodeFramedRepositorySelection(source.selection, short, 1, 32,
    ByteLimit(high(uint64))).error == RepositoryError.LimitExceeded
  reset(0)
  let frame = encodeRepositorySnapshot(source.selection, default(StorageChainId),
    StorageSchema.FullStateV1, [1'u8, 2], source.limits).value
  var exact = source.limits
  exact.bytes = ByteLimit(frame.bytes.len)
  reset(0)
  assert encodeRepositorySnapshot(source.selection, default(StorageChainId),
    StorageSchema.FullStateV1, [1'u8, 2], exact).value.bytes == frame.bytes
  assert calls() == 1
  exact.bytes = ByteLimit(frame.bytes.len-1)
  reset(0)
  assert encodeRepositorySnapshot(source.selection, default(StorageChainId),
    StorageSchema.FullStateV1, [1'u8, 2], exact).error != SnapshotError.None
  assert calls() == 0 # Whole-frame refusal precedes its sole checksum and exposes no partial output.

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
  block:
    var framed = encodeFramedRepositorySelection(source.selection, source.limits.repository.codec,
      133, 32, source.limits.bytes)
    let bytes = framed.takeValue
    let retained = getOccupiedMem()-before
    assert retained > 0 and retained <= bytes.len+bytes.len div 8+4096
  assert getOccupiedMem() == before

let policy = snapshotPolicy()
let uninitialized = encodeRepositorySelection(default(RepositorySelection), policy.repository.codec)
assert uninitialized.error == RepositoryError.Uninitialized
let emptyFrame = encodeFramedRepositorySelection(default(RepositorySelection),
  policy.repository.codec, high(uint64), high(uint64), ByteLimit(0))
assert emptyFrame.error == RepositoryError.Uninitialized
framing(snapshotFixture(2, 1))
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
