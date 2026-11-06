# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_segment_batches_arc_release"}

## Genuine roots, literal malformed groups and aggregate work ceilings exercise complete CE139/140/148 serving.
import std/[assertions, syncio]
import ../../../src/jamnp-s/[read_stream, segment_request, availability_read, availability_proof, availability_merkle]
import ../../../src/state/availability/specifier
import ../../../src/state/erasure/[layout, words]
import "../../../src/state/export/erasure" as export_erasure
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
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(packet)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_segment_batches", 1000, before, after)
  echo "JAMNP-S segment batch serving passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
main()
