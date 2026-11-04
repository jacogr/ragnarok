# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_availability_proofs_arc_release"}

## Genuine independent availability commitments authenticate NP distribution/audit/segment data with exact coordinates and bounded work.
import std/[assertions, syncio]
import ../../../src/jamnp-s/[availability_proof, availability_merkle, availability_read, read_stream]
import ../../../src/state/availability/specifier
import ../../../src/state/erasure/[layout, words]
import "../../../src/state/export/erasure" as export_erasure
import ../../../src/codec/bounded
from ../../../src/codec/work/report import BundleLength, ErasureShards, SegmentCount
import ../../support/[pvm_computed_report, arc_evidence]
proc limits(): AvailabilityMerkleLimits =
  ## Explicit source/verification ceilings cover real fixture rows and the full validator leaf set.
  AvailabilityMerkleLimits(bytes: ByteLimit(500000), hashBytes: ByteLimit(16000000),
      hashes: ElementLimit(10000))
proc requested(source: AvailabilityCommitment, kind: AvailabilityTransferKind,
    shard, row: uint64): AvailabilityRequest =
  ## Only test-owned genuine source facts select the expected commitment; no response-supplied root becomes authority.
  AvailabilityRequest(kind: kind, root: source.availabilityInfo.value.specifier.erasureRoot,
    shard: ErasureShardIndex(shard), row: ExportErasureIndex(row))
proc check(source: AvailabilityCommitment, kind: AvailabilityTransferKind, shard, row: uint64) =
  ## Existing component commitments are computed independently of the new trace/reconstruction implementation.
  let request = requested(source, kind, shard, row)
  let prepared = prepareAvailabilityTransfer(source, request, limits())
  assert prepared.error == AvailabilityTransferError.None, "prepare kind=" & $kind & ", reason=" &
      $prepared.error
  let packet = prepared.value
  var bundle = packet.bundleShard
  var segments = packet.segmentShards
  var proof = packet.justification
  let expected = source.availabilityInfo.value.specifier
  let checked = verifyAvailabilityTransfer(expected, request, bundle, segments, proof, limits())
  assert checked.error == AvailabilityTransferError.None, "verify kind=" & $kind & ", reason=" & $checked.error
  assert checked.value.valid and packet.valid
  assert checked.value.request.root.bytes == expected.erasureRoot.bytes
  assert checked.value.specifier.erasureRoot.bytes == expected.erasureRoot.bytes
  assert uint64(checked.value.request.shard) == shard and uint64(checked.value.request.row) == row
  if kind == AvailabilityTransferKind.Audit:
    assert segments.len == 0
  elif kind == AvailabilityTransferKind.Segment:
    assert bundle.len == 0
  let beforeBundle = checked.value.bundleShard
  let beforeSegments = checked.value.segmentShards
  let beforeProof = checked.value.justification
  if bundle.len > 0: bundle[0] = bundle[0] xor 1
  if segments.len > 0: segments[0] = segments[0] xor 1
  proof[0] = proof[0] xor 1
  assert checked.value.bundleShard == beforeBundle and checked.value.segmentShards == beforeSegments
  assert checked.value.justification == beforeProof and packet.justification == beforeProof
proc retained(): PreparedAvailabilityTransfer =
  ## Return only source-free proof/data; every original execution/state/commitment alias retires before the caller uses it.
  let source = computedAvailability(0)
  let prepared = prepareAvailabilityTransfer(source, requested(source,
      AvailabilityTransferKind.Audit, 0, 0), limits())
  assert prepared.error == AvailabilityTransferError.None
  prepared.value
proc releaseCycle(source: AvailabilityCommitment) =
  ## Every new prepared/verified owner and independent byte copy retires before the next ARC sample.
  let request = requested(source, AvailabilityTransferKind.Audit, 0, 0)
  let prepared = prepareAvailabilityTransfer(source, request, limits())
  assert prepared.error == AvailabilityTransferError.None
  let packet = prepared.value
  let checked = verifyAvailabilityTransfer(packet.specifier, request, packet.bundleShard,
    packet.segmentShards, packet.justification, limits())
  assert checked.error == AvailabilityTransferError.None
proc serving(source: AvailabilityCommitment) =
  ## Exact wire framing and existing method ceilings remain independent of proof construction.
  let expected = source.availabilityInfo.value.specifier
  var payload: seq[byte] = @[]
  for octet in expected.erasureRoot.bytes: payload.add(octet)
  let bundle = decodeReadRequest(ReadKind.Bundle, payload).value
  payload.add(0)
  payload.add(0)
  let shards = decodeReadRequest(ReadKind.Availability, payload).value
  let policy = AvailabilityReadLimits(computation: AvailabilityMerkleLimits(
    bytes: ByteLimit(64000000), hashBytes: ByteLimit(16000000), hashes: ElementLimit(10000)),
    wireBytes: ByteLimit(16000000))
  assert not default(AvailabilityReadLimits).valid and policy.valid
  assert serveAvailabilityRead(source, bundle, default(AvailabilityReadLimits)).error ==
      ReadError.LimitExceeded
  assert serveAvailabilityRead(default(AvailabilityCommitment), bundle, policy).error ==
      ReadError.Unavailable
  let complete = serveAvailabilityRead(source, bundle, policy)
  assert complete.error == ReadError.None
  assert complete.value.byteLength == int(uint32(expected.bundleLength))+4
  let distributed = serveAvailabilityRead(source, shards, policy)
  assert distributed.error == ReadError.None and distributed.value.byteLength > 12
  payload[0] = payload[0] xor 1
  assert serveAvailabilityRead(source, decodeReadRequest(ReadKind.Availability, payload).value,
    policy).error == ReadError.Unavailable
  payload[0] = payload[0] xor 1
  payload[32] = 255
  payload[33] = 255
  assert serveAvailabilityRead(source, decodeReadRequest(ReadKind.Availability, payload).value,
    policy).error == ReadError.InvalidRequest
  var refused = policy
  refused.computation.bytes = ByteLimit(1)
  assert serveAvailabilityRead(source, shards, refused).error == ReadError.LimitExceeded
  refused = policy
  refused.computation.hashes = ElementLimit(1)
  assert serveAvailabilityRead(source, shards, refused).error == ReadError.LimitExceeded
  refused = policy
  refused.wireBytes = ByteLimit(4)
  assert serveAvailabilityRead(source, bundle, refused).error == ReadError.LimitExceeded
  var oversized = newSeq[byte](MaxReadReplyBytes+5)
  let size = oversized.len-4
  for index in 0..<4: oversized[index] = byte((uint32(size) shr (8*index)) and 255)
  assert captureReadReply(bundle, oversized).error == ReadError.None
  let ordinary = decodeReadRequest(ReadKind.Report, expected.erasureRoot.bytes).value
  assert captureReadReply(ordinary, oversized).error == ReadError.LimitExceeded
proc main() =
  ## Exercise empty segment trees, odd populations and both export/proof-page row boundaries with genuine PVM/erasure sources.
  let empty = computedAvailability(0)
  for shard in [0'u64, 3, 5]:
    check(empty, AvailabilityTransferKind.Distribution, shard, 0)
    check(empty, AvailabilityTransferKind.Audit, shard, 0)
  serving(empty)
  let populated = computedAvailability(1)
  for shard in [0'u64, 511, 1022]:
    check(populated, AvailabilityTransferKind.Distribution, shard, 0)
    check(populated, AvailabilityTransferKind.Audit, shard, 0)
    check(populated, AvailabilityTransferKind.Segment, shard, 0)
    check(populated, AvailabilityTransferKind.Segment, shard, 1)
  let paged = computedAvailability(65)
  for row in [0'u64, 64, 65, 66]: check(paged, AvailabilityTransferKind.Segment, 0, row)
  check(paged, AvailabilityTransferKind.Distribution, 5, 0)
  let request = requested(populated, AvailabilityTransferKind.Segment, 0, 0)
  let packet = prepareAvailabilityTransfer(populated, request, limits()).value
  let expected = populated.availabilityInfo.value.specifier
  let body = packet.segmentShards
  let proof = packet.justification
  for extent in 0..<proof.len:
    # All tag/payload truncations refuse the whole transfer, including the explicit middle bundle hash.
    let prefix = if extent == 0: newSeq[byte](0) else: proof[0..<extent]
    assert verifyAvailabilityTransfer(expected, request, [], body, prefix, limits()).error ==
        AvailabilityTransferError.InvalidProof
  var corrupted = proof
  corrupted.add(0)
  assert verifyAvailabilityTransfer(expected, request, [], body, corrupted, limits()).error ==
      AvailabilityTransferError.InvalidProof
  corrupted = proof
  let outer = availabilityTraceWork(64, 1023, 0, 1).value
  corrupted[int(outer.proofBytes)] = 1
  assert verifyAvailabilityTransfer(expected, request, [], body, corrupted, limits()).error ==
      AvailabilityTransferError.InvalidProof
  corrupted = body
  corrupted[0] = corrupted[0] xor 1
  assert verifyAvailabilityTransfer(expected, request, [], corrupted, proof, limits()).error !=
      AvailabilityTransferError.None
  assert verifyAvailabilityTransfer(expected, request, [0'u8], body, proof, limits()).error ==
      AvailabilityTransferError.InvalidPayload
  assert verifyAvailabilityTransfer(expected, request, [], body.toOpenArray(0, body.len-2), proof,
      limits()).error == AvailabilityTransferError.InvalidPayload
  var wrong = request
  wrong.root.bytes[0] = wrong.root.bytes[0] xor 1
  assert prepareAvailabilityTransfer(populated, wrong, limits()).error ==
      AvailabilityTransferError.RootMismatch
  assert verifyAvailabilityTransfer(expected, wrong, [], body, proof, limits()).error ==
      AvailabilityTransferError.RootMismatch
  wrong = request
  wrong.shard = ErasureShardIndex(high(uint64))
  assert prepareAvailabilityTransfer(populated, wrong, limits()).error ==
      AvailabilityTransferError.InvalidIndex
  wrong = request
  wrong.row = ExportErasureIndex(high(uint64))
  assert prepareAvailabilityTransfer(populated, wrong, limits()).error ==
      AvailabilityTransferError.InvalidIndex
  let unavailable = prepareAvailabilityTransfer(default(AvailabilityCommitment), request, limits())
  assert unavailable.error == AvailabilityTransferError.SourceFailure
  assert unavailable.sourceError == AvailabilityCommitmentError.Uninitialized
  assert prepareAvailabilityTransfer(empty, requested(empty, AvailabilityTransferKind.Segment, 0,
      0), limits()).error == AvailabilityTransferError.InvalidIndex
  var metadata = expected
  metadata.bundleLength = BundleLength(MaxAvailabilityBundleBytes+1)
  assert verifyAvailabilityTransfer(metadata, request, [], body, proof, limits()).error ==
      AvailabilityTransferError.InvalidSpecifier
  metadata = expected
  metadata.erasureShards = ErasureShards(5)
  let geometry = verifyAvailabilityTransfer(metadata, request, [], body, proof, limits())
  assert geometry.error == AvailabilityTransferError.GeometryFailure and geometry.geometryError ==
      ErasureLayoutError.InvalidShards
  metadata = expected
  metadata.segmentCount = SegmentCount(3073)
  assert verifyAvailabilityTransfer(metadata, request, [], body, proof, limits()).error ==
      AvailabilityTransferError.InvalidSpecifier
  let auditRequest = requested(empty, AvailabilityTransferKind.Audit, 0, 0)
  let audit = prepareAvailabilityTransfer(empty, auditRequest, limits()).value
  var cap = limits()
  cap.hashes = ElementLimit(5) # Outer construction has five calls and bundle hashing needs a sixth; independent full child caps must not multiply allowance.
  assert prepareAvailabilityTransfer(empty, auditRequest, cap).error ==
      AvailabilityTransferError.LimitExceeded
  cap = limits()
  cap.hashes = ElementLimit(3) # This received path has three outer hashes plus one bundle hash.
  assert verifyAvailabilityTransfer(audit.specifier, auditRequest, audit.bundleShard, [],
      audit.justification, cap).error == AvailabilityTransferError.LimitExceeded
  cap = limits()
  cap.bytes = ByteLimit(0)
  assert prepareAvailabilityTransfer(empty, auditRequest, cap).error ==
      AvailabilityTransferError.LimitExceeded
  assert verifyAvailabilityTransfer(audit.specifier, auditRequest, audit.bundleShard, [],
      audit.justification, cap).error == AvailabilityTransferError.LimitExceeded
  cap = limits()
  cap.hashBytes = ByteLimit(0)
  assert prepareAvailabilityTransfer(empty, auditRequest, cap).error ==
      AvailabilityTransferError.LimitExceeded
  let frozen = retained()
  assert verifyAvailabilityTransfer(frozen.specifier, frozen.request, frozen.bundleShard,
    frozen.segmentShards, frozen.justification, limits()).error == AvailabilityTransferError.None
  assert not default(PreparedAvailabilityTransfer).valid and not default(
      VerifiedAvailabilityTransfer).valid
  releaseCycle(empty)
  let before = getOccupiedMem()
  for iteration in 0..<1000: releaseCycle(empty)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_availability_proofs", 1000, before, after)
  echo "JAMNP-S authenticated availability transfers passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
main()
