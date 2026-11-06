# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original report-backed CE137/147 computation produces detached exact-framed replies only under a managed CPU lease.
import ./[availability_proof, availability_merkle, read_stream]
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
  uint64(limits.wireBytes) >= 4 and uint64(limits.wireBytes) <= 16'u64*1024*1024 and
    uint64(limits.computation.bytes) > 0 and uint64(limits.computation.bytes) <=
        128'u64*1024*1024 and
    uint64(limits.computation.hashBytes) > 0 and uint64(limits.computation.hashBytes) <=
        32'u64*1024*1024 and
    uint64(limits.computation.hashes) > 0 and uint64(limits.computation.hashes) <= 10000
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
  let maximum = uint64(limits.wireBytes)
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
