# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original report-backed CE137/147 computation produces detached exact-framed replies only under a managed CPU lease.
import ./[availability_proof, availability_merkle, read_stream, segment_request]
import ../codec/natural
import "../state/export/commitment" as export_commitment
import ../codec/bounded
import ../state/availability/specifier
import ../state/erasure/[layout, words]
import ../state/bundle_erasure
import ../state/auditable_bundle
import "../state/export/erasure" as export_erasure

type AvailabilityReadLimits* = object ## Explicit computation and final-wire ceilings keep optional serving disabled by default.
  computation*: AvailabilityMerkleLimits
  wireBytes*: ByteLimit
func valid*(limits: AvailabilityReadLimits): bool =
  ## Local policy is finite independently of request counts and source metadata; no zero field acquires a guessed default.
  uint64(limits.wireBytes) >= 4 and uint64(limits.wireBytes) <= 32'u64*1024*1024 and
    uint64(limits.computation.bytes) > 0 and uint64(limits.computation.bytes) <=
        256'u64*1024*1024 and
    uint64(limits.computation.hashBytes) > 0 and uint64(limits.computation.hashBytes) <=
        128'u64*1024*1024 and
    uint64(limits.computation.hashes) > 0 and uint64(limits.computation.hashes) <= 1000000
func availabilityRead*(request: ReadRequest): bool =
  ## This source family never handles ordinary canonical content or upload acknowledgments.
  request.valid and request.kind in [ReadKind.Availability, ReadKind.Bundle]
proc matchesAvailability*(request: ReadRequest, expected: AvailabilitySpecifier): bool =
  ## Compare fixed root bytes before retaining any source-bearing owner; shard range remains a computation check.
  if not request.availabilityRead: return false
  let payload = request.payload
  for index in 0..<32:
    if payload[index] != expected.erasureRoot.bytes[index]: return false
  true
proc appendMessage(output: var seq[byte], payload: openArray[byte]) =
  ## Callers precharge every output byte and only pass hard-bounded complete payloads.
  for index in 0..<4: output.add(byte((uint32(payload.len) shr (8*index)) and 255))
  for octet in payload: output.add(octet)
proc serveAvailabilityRead*(source: AvailabilityCommitment, request: ReadRequest,
    limits: AvailabilityReadLimits): ReadResult[ReadReply] =
  ## Only the CPU worker accesses source aliases; the returned reply owns bytes and no canonical graph.
  if not request.availabilityRead: return readFailure[ReadReply](ReadError.InvalidRequest)
  if not limits.valid: return readFailure[ReadReply](ReadError.LimitExceeded)
  let info = source.availabilityInfo
  if info.error != AvailabilityCommitmentError.None: return readFailure[ReadReply](
      ReadError.Unavailable)
  if not request.matchesAvailability(info.value.specifier): return readFailure[ReadReply](
      ReadError.Unavailable)
  let maximum = min(uint64(limits.wireBytes), uint64(request.maximumReplyBytes))
  let reservation = maximum*3 # Maximum16MiB proves multiplication; getters, framed output and frozen reply all fit.
  if uint64(limits.computation.bytes) < reservation:
    return readFailure[ReadReply](ReadError.LimitExceeded)
  var wire: seq[byte] = @[]
  if request.kind == ReadKind.Bundle:
    let length = uint64(uint32(info.value.specifier.bundleLength))
    if length == 0 or length > MaxAvailabilityBundleBytes or length+4 > maximum:
      return readFailure[ReadReply](ReadError.LimitExceeded)
    let bundle = source.availabilitySource.value.exportErasureSource.value.bundleErasureSource.value.layoutSource.value
    let payload = bundle.bundleBytes
    if payload.error != AuditableBundleError.None: return readFailure[ReadReply](
        ReadError.Unavailable)
    appendMessage(wire, payload.value)
  else:
    let payload = request.payload
    let index = uint64(payload[32]) or (uint64(payload[33]) shl 8)
    let selected = AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
      root: info.value.specifier.erasureRoot, shard: ErasureShardIndex(index))
    var budget = limits.computation
    budget.bytes = ByteLimit(uint64(budget.bytes)-reservation)
    let prepared = prepareAvailabilityTransfer(source, selected, budget)
    case prepared.error
    of AvailabilityTransferError.None: discard # Only complete construction permits any framed reply bytes.
    of AvailabilityTransferError.LimitExceeded: return readFailure[ReadReply](
        ReadError.LimitExceeded)
    of AvailabilityTransferError.InvalidIndex: return readFailure[ReadReply](
        ReadError.InvalidRequest)
    else: return readFailure[ReadReply](ReadError.Unavailable)
    let transfer = prepared.value
    let bundle = transfer.bundleShard
    let segments = transfer.segmentShards
    let proof = transfer.justification
    let total = uint64(bundle.len)+uint64(segments.len)+uint64(proof.len)+12
    if total > maximum: return readFailure[ReadReply](ReadError.LimitExceeded)
    appendMessage(wire, bundle)
    appendMessage(wire, segments)
    appendMessage(wire, proof)
  captureReadReply(request, wire)

proc serveAvailabilityAudit*(source: VerifiedAvailabilityTransfer, request: ReadRequest,
    limits: AvailabilityReadLimits): ReadResult[ReadReply] =
  ## Assurers need only their privately retained verified distribution, never the guarantor's execution graph.
  if not request.valid or request.kind != ReadKind.Audit: return readFailure[ReadReply](
      ReadError.InvalidRequest)
  if not limits.valid: return readFailure[ReadReply](ReadError.LimitExceeded)
  if not source.valid: return readFailure[ReadReply](ReadError.Unavailable)
  if source.request.kind != AvailabilityTransferKind.Distribution: return readFailure[ReadReply](
      ReadError.Unavailable)
  let payload = request.payload
  let expected = source.specifier
  for index in 0..<32:
    if payload[index] != expected.erasureRoot.bytes[index]: return readFailure[ReadReply](
        ReadError.Unavailable)
  let index = uint64(payload[32]) or (uint64(payload[33]) shl 8)
  let maximum = min(uint64(limits.wireBytes), uint64(request.maximumReplyBytes))
  let reservation = maximum*3 # Both independent hard ceilings prove this subtraction and all detached copies.
  if uint64(limits.computation.bytes) < reservation: return readFailure[ReadReply](
      ReadError.LimitExceeded)
  var budget = limits.computation
  budget.bytes = ByteLimit(uint64(budget.bytes)-reservation)
  let selected = AvailabilityRequest(kind: AvailabilityTransferKind.Audit,
    root: expected.erasureRoot, shard: ErasureShardIndex(index))
  let prepared = prepareAvailabilityAudit(source, selected, budget)
  case prepared.error
  of AvailabilityTransferError.None: discard # Only a complete original-path derivation can produce transport bytes.
  of AvailabilityTransferError.LimitExceeded: return readFailure[ReadReply](ReadError.LimitExceeded)
  of AvailabilityTransferError.InvalidIndex: return readFailure[ReadReply](ReadError.InvalidRequest)
  else: return readFailure[ReadReply](ReadError.Unavailable)
  let bundle = prepared.value.bundleShard
  let proof = prepared.value.justification
  if uint64(bundle.len)+uint64(proof.len)+8 > maximum: return readFailure[ReadReply](
      ReadError.LimitExceeded)
  var wire: seq[byte] = @[]
  appendMessage(wire, bundle)
  appendMessage(wire, proof)
  captureReadReply(request, wire)

func batchSource(sources: openArray[VerifiedAvailabilityTransfer], item: SegmentSelection): int =
  ## Early returns select one exact root/shard without carrying a mutable sentinel through nested loop exits.
  for index in 0..<sources.len:
    if not sources[index].valid: continue
    let key = sources[index].request
    if key.kind == AvailabilityTransferKind.Distribution and key.root.bytes == item.root and uint64(
        key.shard) == uint64(item.shard):
      return index
  -1
proc serveSegmentShardBatch*(sources: openArray[VerifiedAvailabilityTransfer], request: ReadRequest,
    limits: AvailabilityReadLimits): ReadResult[ReadReply] =
  ## One managed turn precharges the entire ordered batch and indexes each selected verified distribution once.
  if not request.valid or request.kind notin [ReadKind.SegmentShards, ReadKind.ProvenSegmentShards]:
    return readFailure[ReadReply](ReadError.InvalidRequest)
  if not limits.valid or sources.len > 64: return readFailure[ReadReply](ReadError.LimitExceeded)
  let maximum = min(uint64(limits.wireBytes), uint64(request.maximumReplyBytes))
  let base = maximum*3+uint64(request.payloadLength)*2+uint64(request.itemCount)*64
  if base > uint64(limits.computation.bytes): return readFailure[ReadReply](ReadError.LimitExceeded)
  let parsed = segmentSelections(request.kind.segmentKind, request.payload)
  if parsed.error != SegmentRequestError.None: return readFailure[ReadReply](
      ReadError.InvalidRequest)
  let selected = parsed.value
  var sourceRows = newSeq[int](selected.len)
  var needed = default(array[64, bool])
  var trees = default(array[64, StoredSegmentProofs])
  var work = default(array[64, StoredSegmentWork])
  var dataBytes, proofBytes, hashBytes, hashes, bytes = 0'u64
  for ordinal, item in selected:
    # No bytes/hash work are extracted until all roots, coordinates, output extents and aggregate resources pass.
    let found = batchSource(sources, item)
    if found < 0: return readFailure[ReadReply](ReadError.Unavailable)
    let specifier = sources[found].specifier
    let count = uint64(uint16(specifier.segmentCount))
    let rows = int(count+(count+63) div 64)
    if int(item.index) >= rows: return readFailure[ReadReply](ReadError.InvalidRequest)
    let geometry = erasureGeometry(specifier.bundleLength, specifier.erasureShards)
    if geometry.error != ErasureLayoutError.None: return readFailure[ReadReply](
        ReadError.InvalidRequest)
    let width = int(geometry.value.segmentChunkBytes)
    dataBytes += uint64(width)
    sourceRows[ordinal] = found
    if request.kind == ReadKind.ProvenSegmentShards:
      let outer = availabilityTraceWork(64, int(uint16(specifier.erasureShards)), int(item.shard), 1)
      let inner = availabilityTraceWork(width, rows, int(item.index), 2)
      if outer.error != AvailabilityMerkleError.None or inner.error != AvailabilityMerkleError.None:
        return readFailure[ReadReply](ReadError.InvalidRequest)
      proofBytes += outer.value.proofBytes+33+inner.value.proofBytes+4
      if not needed[found]:
        let described = storedSegmentWork(sources[found])
        if described.error != AvailabilityTransferError.None: return readFailure[ReadReply](
            ReadError.InvalidRequest)
        work[found] = described.value
        bytes += described.value.bytes
        hashBytes += described.value.hashBytes
        hashes += described.value.hashes
        needed[found] = true
  if dataBytes+proofBytes+4 > maximum or bytes > uint64(limits.computation.bytes)-base or
      hashes > uint64(limits.computation.hashes) or hashBytes > uint64(
          limits.computation.hashBytes):
    return readFailure[ReadReply](ReadError.LimitExceeded)
  for index in 0..<sources.len:
    if needed[index]:
      let prepared = prepareStoredSegmentProofs(sources[index], AvailabilityMerkleLimits(
        bytes: ByteLimit(work[index].bytes), hashes: ElementLimit(work[index].hashes),
            hashBytes: ByteLimit(work[index].hashBytes)))
      if prepared.error != AvailabilityTransferError.None: return readFailure[ReadReply](
          ReadError.Unavailable)
      trees[index] = prepared.value
  var data = newSeq[byte](int(dataBytes))
  var proofs = newSeq[seq[byte]](if request.kind ==
      ReadKind.ProvenSegmentShards: selected.len else: 0)
  var offset = 0
  for ordinal, item in selected:
    let index = sourceRows[ordinal]
    let row = ExportErasureIndex(uint64(item.index))
    if request.kind == ReadKind.ProvenSegmentShards:
      let prepared = storedAvailabilitySegment(trees[index], row, ByteLimit(10000))
      if prepared.error != AvailabilityTransferError.None: return readFailure[ReadReply](
          ReadError.Unavailable)
      let chunk = prepared.value.segmentShards
      for position in 0..<chunk.len: data[offset+position] = chunk[position]
      offset += chunk.len
      proofs[ordinal] = prepared.value.justification
    else:
      let chunk = storedAvailabilityRow(sources[index], row, ByteLimit(1368))
      if chunk.error != AvailabilityTransferError.None: return readFailure[ReadReply](
          ReadError.Unavailable)
      for position in 0..<chunk.value.len: data[offset+position] = chunk.value[position]
      offset += chunk.value.len
  var wire: seq[byte] = @[]
  appendMessage(wire, data)
  for proof in proofs: appendMessage(wire, proof)
  captureReadReply(request, wire)
proc serveOriginalSegmentBatch*(source: AvailabilityCommitment, request: ReadRequest,
    limits: AvailabilityReadLimits): ReadResult[ReadReply] =
  ## CE148 returns actual final normalized exports and constant-depth proofs from the original computed report.
  if not request.valid or request.kind != ReadKind.Segments: return readFailure[ReadReply](
      ReadError.InvalidRequest)
  if not limits.valid: return readFailure[ReadReply](ReadError.LimitExceeded)
  let maximum = min(uint64(limits.wireBytes), uint64(request.maximumReplyBytes))
  let base = maximum*3+uint64(request.payloadLength)*2+uint64(request.itemCount)*64
  if base > uint64(limits.computation.bytes): return readFailure[ReadReply](ReadError.LimitExceeded)
  let described = source.availabilityInfo
  if described.error != AvailabilityCommitmentError.None: return readFailure[ReadReply](
      ReadError.Unavailable)
  let parsed = segmentSelections(SegmentRequestKind.Segments, request.payload)
  if parsed.error != SegmentRequestError.None: return readFailure[ReadReply](
      ReadError.InvalidRequest)
  let selected = parsed.value
  let expected = described.value.specifier
  let count = int(uint16(expected.segmentCount))
  var depth, capacity = 0
  capacity = 1
  while capacity < count:
    capacity *= 2
    inc depth
  let total = uint64(selected.len)*(4105'u64+uint64(depth)*32)+8
  if total > maximum: return readFailure[ReadReply](ReadError.LimitExceeded)
  for item in selected:
    if item.root != expected.segmentRoot.bytes: return readFailure[ReadReply](ReadError.Unavailable)
    if int(item.index) >= count: return readFailure[ReadReply](ReadError.InvalidRequest)
  let commitment = source.availabilitySource.value.exportErasureCommitment.value
  var segments = newSeq[byte](selected.len*4104)
  var proofs: seq[byte] = @[]
  for ordinal, item in selected:
    let index = ExportSegmentIndex(uint64(item.index))
    let segment = commitment.commitmentSegment(index)
    let path = commitment.commitmentPath(index)
    if segment.error != ExportCommitmentError.None or path.error != ExportCommitmentError.None:
      return readFailure[ReadReply](ReadError.Unavailable)
    let raw = array[4104, byte](segment.value)
    for position in 0..<4104: segments[ordinal*4104+position] = raw[position]
    let prefix = encode(JamNatural(uint64(path.value.len)))
    for position in 0..<prefix.len: proofs.add(prefix.bytes[position])
    for sibling in path.value:
      for octet in sibling.bytes: proofs.add(octet)
  var wire: seq[byte] = @[]
  appendMessage(wire, segments)
  appendMessage(wire, proofs)
  captureReadReply(request, wire)
