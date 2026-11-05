# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_availability_proofs_arc_release"}

## Genuine independent availability commitments authenticate NP distribution/audit/segment data with exact coordinates and bounded work.
import std/[assertions, syncio]
import ../../../src/jamnp-s/[availability_proof, availability_merkle, availability_read,
    availability_store, read_stream]
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
proc retentionLimits(): AvailabilityMerkleLimits =
  ## Whole-report retention budgets cover all 1023 real validator coordinates and their complete independent proofs.
  AvailabilityMerkleLimits(bytes: ByteLimit(128*1024*1024),
    hashBytes: ByteLimit(512*1024*1024), hashes: ElementLimit(8000000))
proc retainedGuarantor(): GuarantorAvailability =
  ## Return serving data only after all original execution, canonical map and erasure commitment aliases retire.
  let source = computedAvailability(0)
  let retained = retainGuarantorAvailability(source, retentionLimits())
  assert retained.error == AvailabilityTransferError.None
  retained.value
proc retainedReadLimits(): AvailabilityReadLimits =
  ## Bounded detached response copies do not need fresh hashes, but ordinary serving policy remains explicit and independently valid.
  AvailabilityReadLimits(computation: AvailabilityMerkleLimits(bytes: ByteLimit(64000000),
    hashBytes: ByteLimit(16000000), hashes: ElementLimit(10000)), wireBytes: ByteLimit(16000000))
proc retainedRequest(owner: GuarantorAvailability, kind: ReadKind,
    shard: uint64 = 0): ReadRequest =
  ## Only immutable captured commitment facts select the original root; query parsing still validates exact NP framing.
  var payload: seq[byte] = @[]
  for octet in owner.guarantorInfo.value.specifier.erasureRoot.bytes: payload.add(octet)
  if kind == ReadKind.Availability:
    payload.add(byte(shard and 255))
    payload.add(byte((shard shr 8) and 255))
  decodeReadRequest(kind, payload).value
proc checkRetention(owner: GuarantorAvailability, shard: uint64) =
  ## Independently verify an archived full distribution against its original computed specifier and exact coordinate.
  let info = owner.guarantorInfo.value
  let selected = owner.guarantorTransfer(ErasureShardIndex(shard))
  assert selected.error == AvailabilityTransferError.None
  let packet = selected.value
  let request = AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
    root: info.specifier.erasureRoot, shard: ErasureShardIndex(shard))
  let checked = verifyAvailabilityTransfer(info.specifier, request, packet.bundleShard,
    packet.segmentShards, packet.justification, limits())
  assert checked.error == AvailabilityTransferError.None
  assert uint64(packet.specifier.erasureShards) == uint64(info.specifier.erasureShards)
  assert serveAvailabilityRead(owner, retainedRequest(owner, ReadKind.Availability, shard),
      retainedReadLimits()).error == ReadError.None
  assert serveAvailabilityRead(owner, retainedRequest(owner, ReadKind.Bundle), retainedReadLimits()).error == ReadError.None
proc retention(source: AvailabilityCommitment) =
  ## Exact aggregate resource boundaries and detached mutations must not alter later shard or bundle serving.
  let readLimits = retainedReadLimits()
  assert not default(GuarantorAvailability).valid
  assert default(GuarantorAvailability).guarantorInfo.error ==
      AvailabilityTransferError.Uninitialized
  assert default(GuarantorAvailability).guarantorBundle.error ==
      AvailabilityTransferError.Uninitialized
  assert default(GuarantorAvailability).guarantorTransfer(ErasureShardIndex(0)).error ==
      AvailabilityTransferError.Uninitialized
  assert retainGuarantorAvailability(source, default(AvailabilityMerkleLimits)).error ==
      AvailabilityTransferError.LimitExceeded
  let invalid = retainGuarantorAvailability(default(AvailabilityCommitment), retentionLimits())
  assert invalid.error == AvailabilityTransferError.SourceFailure
  assert invalid.sourceError == AvailabilityCommitmentError.Uninitialized
  let captured = retainGuarantorAvailability(source, retentionLimits())
  assert captured.error == AvailabilityTransferError.None
  let owner = captured.value
  assert owner.valid
  let info = owner.guarantorInfo.value
  let count = uint64(uint16(info.specifier.erasureShards))
  for shard in [0'u64, count div 2, count-1]:
    # Compare every framed message with independently served original computation, not another archive getter.
    checkRetention(owner, shard)
    let request = retainedRequest(owner, ReadKind.Availability, shard)
    let original = serveAvailabilityRead(source, request, readLimits)
    let archived = serveAvailabilityRead(owner, request, readLimits)
    assert original.error == ReadError.None and archived.error == ReadError.None
    assert original.value.bytes == archived.value.bytes
  let bundleRequest = retainedRequest(owner, ReadKind.Bundle)
  assert serveAvailabilityRead(source, bundleRequest, readLimits).value.bytes ==
      serveAvailabilityRead(owner, bundleRequest, readLimits).value.bytes
  let absentReply = serveAvailabilityRead(default(GuarantorAvailability), bundleRequest, readLimits)
  assert absentReply.error == ReadError.Unavailable
  assert serveAvailabilityRead(owner, bundleRequest, default(AvailabilityReadLimits)).error ==
      ReadError.LimitExceeded
  let excessive = retainedRequest(owner, ReadKind.Availability, count)
  assert serveAvailabilityRead(owner, excessive, readLimits).error ==
      ReadError.InvalidRequest
  var wrong = bundleRequest.payload
  wrong[0] = wrong[0] xor 1
  assert serveAvailabilityRead(owner, decodeReadRequest(ReadKind.Bundle, wrong).value,
      readLimits).error == ReadError.Unavailable
  let report = decodeReadRequest(ReadKind.Report, bundleRequest.payload).value
  assert serveAvailabilityRead(owner, report, readLimits).error ==
      ReadError.InvalidRequest
  var readCap = readLimits
  readCap.wireBytes = ByteLimit(4)
  assert serveAvailabilityRead(owner, bundleRequest, readCap).error == ReadError.LimitExceeded
  assert serveAvailabilityRead(owner, retainedRequest(owner, ReadKind.Availability),
      readCap).error == ReadError.LimitExceeded
  readCap = readLimits
  readCap.computation.bytes = ByteLimit(4)
  assert serveAvailabilityRead(owner, bundleRequest, readCap).error == ReadError.LimitExceeded
  assert owner.guarantorTransfer(ErasureShardIndex(count)).error ==
      AvailabilityTransferError.InvalidIndex
  assert owner.guarantorTransfer(ErasureShardIndex(high(uint64))).error ==
      AvailabilityTransferError.InvalidIndex
  let original = owner.guarantorBundle.value
  assert uint64(original.len) == uint64(uint32(info.specifier.bundleLength))
  var changed = owner.guarantorBundle.value
  changed[0] = changed[0] xor 1
  assert owner.guarantorBundle.value == original
  let packet = owner.guarantorTransfer(ErasureShardIndex(0)).value
  let before = packet.justification
  var damaged = packet.justification
  damaged[0] = damaged[0] xor 1
  assert owner.guarantorTransfer(ErasureShardIndex(0)).value.justification == before
  var cap = retentionLimits()
  cap.bytes = ByteLimit(info.retainedBytes+info.workspaceBytes-1)
  assert retainGuarantorAvailability(source, cap).error == AvailabilityTransferError.LimitExceeded
  cap = retentionLimits()
  cap.hashes = ElementLimit(info.hashes-1)
  assert retainGuarantorAvailability(source, cap).error == AvailabilityTransferError.LimitExceeded
  cap = retentionLimits()
  cap.hashBytes = ByteLimit(info.hashBytes-1)
  assert retainGuarantorAvailability(source, cap).error == AvailabilityTransferError.LimitExceeded
  cap = AvailabilityMerkleLimits(bytes: ByteLimit(info.retainedBytes+info.workspaceBytes),
    hashes: ElementLimit(info.hashes), hashBytes: ByteLimit(info.hashBytes))
  assert retainGuarantorAvailability(source, cap).error == AvailabilityTransferError.None
proc releaseCycle(source: AvailabilityCommitment) =
  ## Every new prepared/verified owner and independent byte copy retires before the next ARC sample.
  let retained = retainGuarantorAvailability(source, retentionLimits())
  assert retained.error == AvailabilityTransferError.None
  assert retained.value.guarantorBundle.value.len > 0
  let request = requested(source, AvailabilityTransferKind.Audit, 0, 0)
  let prepared = prepareAvailabilityTransfer(source, request, limits())
  assert prepared.error == AvailabilityTransferError.None
  let packet = prepared.value
  let checked = verifyAvailabilityTransfer(packet.specifier, request, packet.bundleShard,
    packet.segmentShards, packet.justification, limits())
  assert checked.error == AvailabilityTransferError.None
  let distributionRequest = requested(source, AvailabilityTransferKind.Distribution, 0, 0)
  let distribution = prepareAvailabilityTransfer(source, distributionRequest, limits()).value
  let verified = verifyAvailabilityTransfer(distribution.specifier, distributionRequest,
    distribution.bundleShard, distribution.segmentShards, distribution.justification, limits()).value
  var store = default(AvailabilityStore)
  assert store.configure(AvailabilityStoreLimits(entries: ElementLimit(1), bytes: ByteLimit(500000)))
  assert store.remember(verified) == AvailabilityStoreError.None
  assert prepareAvailabilityAudit(store.find(distributionRequest).value, request, limits()).error ==
      AvailabilityTransferError.None
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
proc distribution(source: AvailabilityCommitment, shard: uint64): VerifiedAvailabilityTransfer =
  ## Genuine preparation is independently checked before any cache admission can occur.
  let request = requested(source, AvailabilityTransferKind.Distribution, shard, 0)
  let prepared = prepareAvailabilityTransfer(source, request, limits()).value
  let checked = verifyAvailabilityTransfer(prepared.specifier, request, prepared.bundleShard,
    prepared.segmentShards, prepared.justification, limits())
  assert checked.error == AvailabilityTransferError.None
  checked.value
proc audit(source: AvailabilityCommitment) =
  ## Derived audit traces match genuine original construction for empty, odd and proof-page geometries.
  let checked = distribution(source, 0)
  let request = requested(source, AvailabilityTransferKind.Audit, 0, 0)
  let derived = prepareAvailabilityAudit(checked, request, limits())
  assert derived.error == AvailabilityTransferError.None
  let original = prepareAvailabilityTransfer(source, request, limits()).value
  assert derived.value.bundleShard == original.bundleShard
  assert derived.value.justification == original.justification
  assert verifyAvailabilityTransfer(checked.specifier, request, derived.value.bundleShard,
    [], derived.value.justification, limits()).error == AvailabilityTransferError.None
  assert prepareAvailabilityAudit(default(VerifiedAvailabilityTransfer), request, limits()).error ==
      AvailabilityTransferError.InvalidPayload
  var wrong = request
  wrong.shard = ErasureShardIndex(1)
  assert prepareAvailabilityAudit(checked, wrong, limits()).error ==
      AvailabilityTransferError.InvalidIndex
  var cap = limits()
  cap.bytes = ByteLimit(0)
  assert prepareAvailabilityAudit(checked, request, cap).error ==
      AvailabilityTransferError.LimitExceeded
  assert detachVerifiedAvailability(checked, ByteLimit(0)).error ==
      AvailabilityTransferError.LimitExceeded
proc storage(source: AvailabilityCommitment) =
  ## Count and byte pressure evict only complete oldest entries; refused inserts preserve previous data.
  let first = distribution(source, 0)
  let second = distribution(source, 1)
  let third = distribution(source, 2)
  var store = default(AvailabilityStore)
  assert store.remember(first) == AvailabilityStoreError.Unconfigured
  assert not store.configure(default(AvailabilityStoreLimits))
  assert store.configure(AvailabilityStoreLimits(entries: ElementLimit(2), bytes: ByteLimit(16000000)))
  assert not store.configure(AvailabilityStoreLimits(entries: ElementLimit(1), bytes: ByteLimit(1)))
  assert store.remember(default(VerifiedAvailabilityTransfer)) ==
      AvailabilityStoreError.InvalidTransfer
  assert store.remember(first) == AvailabilityStoreError.None
  assert store.remember(second) == AvailabilityStoreError.None
  assert store.len == 2 and store.byteLength == first.payloadBytes+second.payloadBytes
  var conflicting = first.specifier
  conflicting.packageHash.bytes[0] = conflicting.packageHash.bytes[0] xor 1
  let conflictingPacket = prepareAvailabilityTransfer(source, first.request, limits()).value
  let conflictingVerified = verifyAvailabilityTransfer(conflicting, first.request,
    conflictingPacket.bundleShard, conflictingPacket.segmentShards,
    conflictingPacket.justification, limits()).value
  assert store.remember(conflictingVerified) == AvailabilityStoreError.Conflict
  assert store.len == 2
  assert store.remember(first) == AvailabilityStoreError.None
  assert store.remember(third) == AvailabilityStoreError.None
  assert store.len == 2 and store.find(second.request).error == AvailabilityStoreError.Missing
  assert store.find(first.request).error == AvailabilityStoreError.None
  let selected = requested(source, AvailabilityTransferKind.Audit, 0, 0)
  let derived = prepareAvailabilityAudit(store.find(first.request).value, selected, limits())
  let auditOnly = verifyAvailabilityTransfer(first.specifier, selected, derived.value.bundleShard,
    [], derived.value.justification, limits()).value
  assert store.remember(auditOnly) == AvailabilityStoreError.InvalidTransfer
  store.clear()
  assert store.len == 0 and store.byteLength == 0
  assert store.configure(AvailabilityStoreLimits(entries: ElementLimit(2), bytes: ByteLimit(
      first.payloadBytes)))
  assert store.remember(first) == AvailabilityStoreError.None
  assert store.remember(second) == AvailabilityStoreError.None
  assert store.len == 1 and store.find(first.request).error == AvailabilityStoreError.Missing
  assert store.find(second.request).error == AvailabilityStoreError.None
  store.clear()
  assert store.configure(AvailabilityStoreLimits(entries: ElementLimit(2), bytes: ByteLimit(
      first.payloadBytes-1)))
  assert store.remember(first) == AvailabilityStoreError.LimitExceeded and store.len == 0
proc main() =
  ## Exercise empty segment trees, odd populations and both export/proof-page row boundaries with genuine PVM/erasure sources.
  let empty = computedAvailability(0)
  for shard in [0'u64, 3, 5]:
    check(empty, AvailabilityTransferKind.Distribution, shard, 0)
    check(empty, AvailabilityTransferKind.Audit, shard, 0)
  serving(empty)
  audit(empty)
  storage(empty)
  retention(empty)
  let detached = retainedGuarantor()
  for shard in [0'u64, 3, 5]: checkRetention(detached, shard)
  let populated = computedAvailability(1)
  retention(populated)
  audit(populated)
  for shard in [0'u64, 511, 1022]:
    check(populated, AvailabilityTransferKind.Distribution, shard, 0)
    check(populated, AvailabilityTransferKind.Audit, shard, 0)
    check(populated, AvailabilityTransferKind.Segment, shard, 0)
    check(populated, AvailabilityTransferKind.Segment, shard, 1)
  let paged = computedAvailability(65)
  audit(paged)
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
