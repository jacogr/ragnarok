# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_segment_batches_arc_release"}

## Genuine roots, literal malformed groups and aggregate work ceilings exercise complete CE139/140/148 serving.
import std/[assertions, syncio]
import ../../../src/jamnp-s/[read_stream, segment_request, availability_read, availability_proof,
    availability_merkle, guarantor_segments]
import ../../../src/state/availability/specifier
import ../../../src/state/erasure/[layout, words]
import "../../../src/state/export/erasure" as export_erasure
import "../../../src/state/export/commitment" as export_commitment
import "../../../src/state/import/justification" as import_proof
import ../../../src/codec/[bounded, natural]
from ../../../src/codec/work/package import ImportIndex
from ../../../src/codec/work/report import SegmentRoot
from ../../../src/pvm/host/fetch import FetchSegment
import ../../support/[pvm_computed_report, arc_evidence, jamnp_segment_batch_fixture]
proc policy(): AvailabilityReadLimits =
  ## Independent explicit computation and wire ceilings admit the genuine bounded sources.
  AvailabilityReadLimits(computation: AvailabilityMerkleLimits(bytes: ByteLimit(64000000),
    hashes: ElementLimit(10000), hashBytes: ByteLimit(16000000)), wireBytes: ByteLimit(4000000))
proc checked(source: AvailabilityCommitment, shard: uint64): VerifiedAvailabilityTransfer =
  ## Only an independently verified complete distribution can populate a source snapshot.
  let expected = source.availabilityInfo.value.specifier
  let request = AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
    root: expected.erasureRoot, shard: ErasureShardIndex(shard))
  let prepared = prepareAvailabilityTransfer(source, request, policy().computation).value
  verifyAvailabilityTransfer(expected, request, prepared.bundleShard, prepared.segmentShards,
    prepared.justification, policy().computation).value
proc cycle(source: VerifiedAvailabilityTransfer) =
  ## Complete request copies, indexed proof contexts, payloads and replies retire on every ARC cycle.
  let payload = segmentGroup(ReadKind.ProvenSegmentShards, source.request.root.bytes, 0, [0'u16, 1, 0])
  let request = decodeReadRequest(ReadKind.ProvenSegmentShards, payload).value
  assert serveSegmentShardBatch([source], request, policy()).error == ReadError.None
proc indexedSources(source: VerifiedAvailabilityTransfer) =
  ## The full NP source bound, default gaps and duplicate coordinates must retain exact replies without a quadratic payload scan or arbitrary 64-source ceiling.
  let payload = segmentGroup(ReadKind.ProvenSegmentShards, source.request.root.bytes,
    uint16(uint64(source.request.shard)), [0'u16, 1, 0])
  let request = decodeReadRequest(ReadKind.ProvenSegmentShards, payload).value
  let expected = serveSegmentShardBatch([source], request, policy()).value.bytes
  var sources = newSeq[VerifiedAvailabilityTransfer](6144)
  for index in 1..<sources.len:
    # Leave the first source default so lower-bound indexing must preserve actual original source positions rather than compressed ordinals.
    sources[index] = source
  let result = serveSegmentShardBatch(sources, request, policy())
  assert result.error == ReadError.None and result.value.bytes == expected,
    "6144 indexed source slots preserve exact repeated-item proof reply"
  sources.add(source)
  assert serveSegmentShardBatch(sources, request, policy()).error == ReadError.LimitExceeded,
    "NP whole-source ceiling rejects 6145 slots before proof allocation"
proc archive(source: AvailabilityCommitment): GuarantorAvailability =
  ## Explicit aggregate capture covers the real 1023-validator source; it grants no canonical report or signing authority.
  let limits = AvailabilityMerkleLimits(bytes: ByteLimit(128*1024*1024),
    hashes: ElementLimit(8000000), hashBytes: ByteLimit(512*1024*1024))
  let retained = retainGuarantorAvailability(source, limits)
  assert retained.error == AvailabilityTransferError.None
  retained.value
proc retainedCycle(source: GuarantorAvailability) =
  ## Every parsed selection, tree, reconstructed original, path and reply retires before the next ARC sample.
  let root = source.guarantorInfo.value.specifier.segmentRoot.bytes
  let request = decodeReadRequest(ReadKind.Segments, segmentGroup(ReadKind.Segments, root, 0, [
      0'u16, 64, 0])).value
  assert serveRetainedSegmentBatch([source], default(AvailabilityCommitment), request, policy()).error == ReadError.None
proc detachedArchive(): GuarantorAvailability =
  ## Original execution and commitment aliases leave scope before the caller reconstructs exports or prepares paths.
  archive(computedAvailability(65))
proc originals(source: AvailabilityCommitment, rows: openArray[uint16]) =
  ## Actual systematic recovery and root-first proofs must match the independent original export commitment byte for byte.
  let retained = archive(source)
  let expected = source.availabilityInfo.value.specifier
  let commitment = source.availabilitySource.value.exportErasureCommitment.value
  let prepared = prepareGuarantorSegments(retained, policy().computation)
  assert prepared.error == GuarantorSegmentError.None
  for row in rows:
    let index = ExportSegmentIndex(uint64(row))
    let segment = retained.guarantorSegment(index)
    assert segment.error == AvailabilityTransferError.None
    assert array[4104, byte](segment.value) == array[4104, byte](commitment.commitmentSegment(index).value)
    assert prepared.value.guarantorSegmentPath(index).value == commitment.commitmentPath(index).value
  let count = uint64(uint16(expected.segmentCount))
  assert retained.guarantorSegment(ExportSegmentIndex(count)).error ==
      AvailabilityTransferError.InvalidIndex
  assert retained.guarantorSegment(ExportSegmentIndex(high(uint64))).error ==
      AvailabilityTransferError.InvalidIndex
  let outside = prepared.value.guarantorSegmentPath(ExportSegmentIndex(count))
  assert outside.error == GuarantorSegmentError.InvalidIndex
  let request = decodeReadRequest(ReadKind.Segments, segmentGroup(ReadKind.Segments,
      expected.segmentRoot.bytes, 0, rows)).value
  let reply = serveRetainedSegmentBatch([retained], default(AvailabilityCommitment), request,
      policy())
  assert reply.error == ReadError.None
  assert reply.value.bytes == serveOriginalSegmentBatch(source, request, policy()).value.bytes
  verifyOriginalSegments(expected, rows, segmentMessages(reply.value.bytes))
  let info = retained.guarantorSegmentPlan.value
  var cap = AvailabilityMerkleLimits(bytes: ByteLimit(info.retainedBytes+info.workspaceBytes),
    hashes: ElementLimit(info.hashes), hashBytes: ByteLimit(info.hashBytes))
  assert prepareGuarantorSegments(retained, cap).error == GuarantorSegmentError.None
  cap.bytes = ByteLimit(info.retainedBytes+info.workspaceBytes-1)
  assert prepareGuarantorSegments(retained, cap).error == GuarantorSegmentError.LimitExceeded
  cap = policy().computation
  cap.hashes = ElementLimit(info.hashes-1)
  assert prepareGuarantorSegments(retained, cap).error == GuarantorSegmentError.LimitExceeded
  cap = policy().computation
  cap.hashBytes = ByteLimit(info.hashBytes-1)
  assert prepareGuarantorSegments(retained, cap).error == GuarantorSegmentError.LimitExceeded
proc retainedBatch(first, second: AvailabilityCommitment) =
  ## A mixed-root batch preserves order and duplicates, builds each tree once, and rejects the whole request on missing or out-of-range data.
  let a = archive(first)
  let b = archive(second)
  let ai = a.guarantorInfo.value.specifier
  let bi = b.guarantorInfo.value.specifier
  assert uint16(ai.segmentCount) == 1 and uint16(bi.segmentCount) == 65
  assert ai.segmentRoot.bytes != bi.segmentRoot.bytes
  var payload = segmentGroup(ReadKind.Segments, bi.segmentRoot.bytes, 0, [64'u16, 0])
  for octet in segmentGroup(ReadKind.Segments, ai.segmentRoot.bytes, 0, [0'u16]): payload.add(octet)
  for octet in segmentGroup(ReadKind.Segments, bi.segmentRoot.bytes, 0, [64'u16]): payload.add(octet)
  let request = decodeReadRequest(ReadKind.Segments, payload).value
  let reply = serveRetainedSegmentBatch([a, b], default(AvailabilityCommitment), request, policy())
  assert reply.error == ReadError.None
  var data, proofs: seq[byte] = @[]
  for ordinal in 0..<4:
    # Independent original computation supplies each exact message fragment; the new tree builder is not its own oracle.
    let original = if ordinal == 2: first else: second
    let expected = original.availabilityInfo.value.specifier
    let row = if ordinal in [0, 3]: 64'u16 else: 0'u16
    let single = decodeReadRequest(ReadKind.Segments, segmentGroup(ReadKind.Segments,
        expected.segmentRoot.bytes, 0, [row])).value
    let parts = segmentMessages(serveOriginalSegmentBatch(original, single, policy()).value.bytes)
    verifyOriginalSegments(expected, [row], parts)
    for octet in parts[0]: data.add(octet)
    for octet in parts[1]: proofs.add(octet)
  let parts = segmentMessages(reply.value.bytes)
  assert parts == @[data, proofs]
  let live = serveRetainedSegmentBatch([b], first, request, policy())
  assert live.error == ReadError.None and live.value.bytes == reply.value.bytes
  var cap = policy()
  cap.computation.hashes = ElementLimit(193) # One export leaf plus65 leaves/127 parents; four selections do not multiply tree work.
  cap.computation.hashBytes = ByteLimit(279764)
  let bytes = uint64(cap.wireBytes)*3+uint64(request.payloadLength)*2+uint64(request.itemCount)*64
  let pa = a.guarantorSegmentPlan.value
  let pb = b.guarantorSegmentPlan.value
  cap.computation.bytes = ByteLimit(bytes+pa.retainedBytes+pb.retainedBytes+max(pa.workspaceBytes,
      pb.workspaceBytes))
  assert serveRetainedSegmentBatch([a, b], default(AvailabilityCommitment), request, cap).error == ReadError.None
  cap.computation.hashes = ElementLimit(192)
  assert serveRetainedSegmentBatch([a, b], default(AvailabilityCommitment), request, cap).error ==
      ReadError.LimitExceeded
  cap.computation.hashes = ElementLimit(193)
  cap.computation.hashBytes = ByteLimit(279763)
  assert serveRetainedSegmentBatch([a, b], default(AvailabilityCommitment), request, cap).error ==
      ReadError.LimitExceeded
  cap.computation.hashBytes = ByteLimit(279764)
  cap.computation.bytes = ByteLimit(uint64(cap.computation.bytes)-1)
  assert serveRetainedSegmentBatch([a, b], default(AvailabilityCommitment), request, cap).error ==
      ReadError.LimitExceeded
  cap = policy()
  cap.computation.hashes = ElementLimit(1)
  cap.computation.hashBytes = ByteLimit(4108)
  let originalFallback = serveRetainedSegmentBatch([a], second, request, cap)
  assert originalFallback.error == ReadError.None and originalFallback.value.bytes ==
      reply.value.bytes
  var unknown = payload
  unknown[0] = unknown[0] xor 1
  let absent = decodeReadRequest(ReadKind.Segments, unknown).value
  let absentReply = serveRetainedSegmentBatch([a, b], default(AvailabilityCommitment), absent,
      policy())
  assert absentReply.error == ReadError.Unavailable
  let invalid = decodeReadRequest(ReadKind.Segments, segmentGroup(ReadKind.Segments,
      bi.segmentRoot.bytes, 0, [65'u16])).value
  let invalidReply = serveRetainedSegmentBatch([a, b], default(AvailabilityCommitment), invalid,
      policy())
  assert invalidReply.error == ReadError.InvalidRequest
  let empty = decodeReadRequest(ReadKind.Segments, []).value
  let nothing = serveRetainedSegmentBatch([], default(AvailabilityCommitment), empty, policy())
  assert nothing.error == ReadError.None and nothing.value.bytes == newSeq[byte](8)
  var largeRows = newSeq[uint16](3072)
  for index in 0..<largeRows.len: largeRows[index] = 64
  let maximum = decodeReadRequest(ReadKind.Segments, segmentGroup(ReadKind.Segments,
      bi.segmentRoot.bytes, 0, largeRows)).value
  cap = policy()
  cap.wireBytes = ByteLimit(16000000)
  cap.computation.hashes = ElementLimit(192)
  assert serveRetainedSegmentBatch([b], default(AvailabilityCommitment), maximum, cap).error == ReadError.None
  cap.computation.hashes = ElementLimit(191)
  assert serveRetainedSegmentBatch([b], default(AvailabilityCommitment), maximum, cap).error ==
      ReadError.LimitExceeded
proc main() =
  ## Incremental byte boundaries and canonical counts precede genuine proof/root and ownership witnesses.
  for kind in [ReadKind.SegmentShards, ReadKind.ProvenSegmentShards, ReadKind.Segments]:
    assert decodeReadRequest(kind, []).error == ReadError.None
    let payload = segmentGroup(kind, default(array[32, byte]), 0, [0'u16, 1, 0])
    let request = decodeReadRequest(kind, payload)
    assert request.error == ReadError.None and request.value.itemCount == 3
    var cursor = initSegmentRequestCursor(kind.segmentKind)
    for octet in payload: assert cursor.consume(octet) == SegmentRequestError.None
    assert cursor.complete and cursor.itemCount == 3
    for extent in 1..<payload.len:
      # A proper prefix ends inside this single nonempty group, never at an alternative valid group boundary.
      assert decodeReadRequest(kind, payload.toOpenArray(0, extent-1)).error ==
          ReadError.InvalidRequest
    var malformed = segmentGroup(kind, default(array[32, byte]), 0, [])
    malformed.setLen(malformed.len-1)
    malformed.add(128)
    malformed.add(0)
    assert decodeReadRequest(kind, malformed).error == ReadError.InvalidRequest
    assert decodeReadRequest(kind, newSeq[byte](kind.segmentKind.maximumPayload+1)).error ==
        ReadError.LimitExceeded
    let detached = detachedReadRequest(request.value)
    var copy = detached.payload
    copy[0] = 1
    assert request.value.payload[0] == 0 and detached.payload[0] == 0
  var unconfigured = default(SegmentRequestCursor)
  assert unconfigured.consume(0) == SegmentRequestError.Uninitialized
  let source = computedAvailability(1)
  let packet = checked(source, 0)
  indexedSources(packet)
  let expected = packet.specifier
  let rows = [0'u16, 1, 0]
  let raw = decodeReadRequest(ReadKind.SegmentShards, segmentGroup(ReadKind.SegmentShards,
      expected.erasureRoot.bytes, 0, rows)).value
  let proven = decodeReadRequest(ReadKind.ProvenSegmentShards, segmentGroup(
      ReadKind.ProvenSegmentShards, expected.erasureRoot.bytes, 0, rows)).value
  let plain = segmentMessages(serveSegmentShardBatch([packet], raw, policy()).value.bytes)
  let proofs = segmentMessages(serveSegmentShardBatch([packet], proven, policy()).value.bytes)
  assert plain.len == 1 and proofs.len == 4 and plain[0] == proofs[0]
  let width = int(erasureGeometry(expected.bundleLength,
      expected.erasureShards).value.segmentChunkBytes)
  for ordinal, row in rows:
    let request = AvailabilityRequest(kind: AvailabilityTransferKind.Segment,
      root: expected.erasureRoot,
      row: ExportErasureIndex(uint64(row)))
    assert verifyAvailabilityTransfer(expected, request, [], proofs[0].toOpenArray(ordinal*width, (
        ordinal+1)*width-1),
      proofs[ordinal+1], policy().computation).error == AvailabilityTransferError.None
  var large = segmentGroup(ReadKind.ProvenSegmentShards, expected.erasureRoot.bytes, 0, [])
  large.setLen(34)
  large.add(152) # Independent canonical natural6144 = 0x98,0x00.
  large.add(0)
  for index in 0..<6144:
    large.add(0)
    large.add(0)
  var exact = policy()
  exact.computation.hashes = ElementLimit(2) # One row-tree hash and one bundle hash, independent of the6144 requested paths.
  let maximum = decodeReadRequest(ReadKind.ProvenSegmentShards, large).value
  assert maximum.itemCount == 6144
  assert serveSegmentShardBatch([packet], maximum, exact).error == ReadError.None
  exact.computation.hashes = ElementLimit(1)
  assert serveSegmentShardBatch([packet], maximum, exact).error == ReadError.LimitExceeded
  large[35] = 1
  assert decodeReadRequest(ReadKind.ProvenSegmentShards, large).error == ReadError.LimitExceeded
  var combined = segmentGroup(ReadKind.ProvenSegmentShards, expected.erasureRoot.bytes, 0, [0'u16])
  for octet in segmentGroup(ReadKind.ProvenSegmentShards, expected.erasureRoot.bytes, 1, [
      0'u16]): combined.add(octet)
  exact = policy()
  exact.computation.hashes = ElementLimit(3)
  assert serveSegmentShardBatch([packet, checked(source, 1)], decodeReadRequest(
      ReadKind.ProvenSegmentShards, combined).value,
    exact).error == ReadError.LimitExceeded
  let paged = computedAvailability(65)
  originals(source, [0'u16, 0])
  originals(paged, [0'u16, 64, 0])
  originals(computedAvailabilityAtCore(1, 0, shards = 12), [0'u16])
  retainedBatch(source, paged)
  let detached = detachedArchive()
  let detachedInfo = detached.guarantorInfo.value.specifier
  let detachedRequest = decodeReadRequest(ReadKind.Segments, segmentGroup(ReadKind.Segments,
      detachedInfo.segmentRoot.bytes, 0, [64'u16, 0])).value
  let detachedReply = serveRetainedSegmentBatch([detached], default(AvailabilityCommitment),
      detachedRequest, policy())
  assert detachedReply.error == ReadError.None
  verifyOriginalSegments(detachedInfo, [64'u16, 0], segmentMessages(detachedReply.value.bytes))
  assert default(GuarantorAvailability).guarantorSegment(ExportSegmentIndex(0)).error ==
      AvailabilityTransferError.Uninitialized
  assert default(GuarantorSegmentTree).guarantorSegmentPath(ExportSegmentIndex(0)).error ==
      GuarantorSegmentError.Uninitialized
  assert prepareGuarantorSegments(default(GuarantorAvailability), policy().computation).error ==
      GuarantorSegmentError.InvalidSource
  let pagedInfo = paged.availabilityInfo.value.specifier
  let originals = [0'u16, 64, 0]
  let request = decodeReadRequest(ReadKind.Segments, segmentGroup(ReadKind.Segments,
      pagedInfo.segmentRoot.bytes, 0, originals)).value
  verifyOriginalSegments(pagedInfo, originals, segmentMessages(serveOriginalSegmentBatch(paged,
      request, policy()).value.bytes))
  assert serveSegmentShardBatch([], proven, policy()).error == ReadError.Unavailable
  let invalid = decodeReadRequest(ReadKind.SegmentShards, segmentGroup(ReadKind.SegmentShards,
      expected.erasureRoot.bytes, 0, [65535'u16])).value
  assert serveSegmentShardBatch([packet], invalid, policy()).error == ReadError.InvalidRequest
  cycle(packet)
  retainedCycle(detached)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(packet)
    retainedCycle(detached)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_segment_batches", 1000, before, after)
  echo "JAMNP-S segment batch serving passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
main()
