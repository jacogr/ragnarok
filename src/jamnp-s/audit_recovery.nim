# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Recover a candidate only from R genuine independently proven original-coordinate CE138 shards. Authentication and actual padding failure remain distinct from local refusal and report evaluation.

import std/assertions
import ./[audit_origin, availability_proof]
from ../codec/work/package import MaxBundleBytes
from ./assurance_store import AssuranceScanControl, stopped
import ../codec/[bounded, report_owned]
import ../codec/work/report
import ../state/availability/specifier
import ../state/erasure/[layout, words]

type
  AuditRecoveryLimits* = object ## Complete copies/workspace and deterministic field products have independent finite ceilings.
    bytes*: ByteLimit
    products*: FieldProductLimit
  RecoveryData = ref object ## Acyclic provenance pins exactly the authenticated original target; no caller validity bit constructs this owner.
    origin: AuditReportOrigin
    invalidPadding: bool
    wire: seq[byte]
  AuditRecoveryEvidence* = object ## Complete authentication may certify an encoding fault rather than a decodable candidate; neither alternative alone signs a judgment.
    data: nil RecoveryData
  AuditRecoveryError* {.pure.} = enum ## Failed/default recovery exposes no authenticated byte or accepted shard prefix.
    Uninitialized, None, InvalidPolicy, InvalidOrigin, InvalidPacket, InvalidCount,
    DuplicateShard, LimitExceeded, Cancelled, GeometryFailure, ReconstructionFailure
  AuditRecoveryResult*[T] = object ## Only complete original-root authentication and actual reconstruction contain evidence.
    case status: AuditRecoveryError
    of None: completed: T
    of GeometryFailure: geometryReason: ErasureLayoutError
    of ReconstructionFailure: reconstructionReason: ErasureWordError
    else: discard # Local refusal carries no successful prefix.

func error*[T](outcome: AuditRecoveryResult[T]): AuditRecoveryError =
  ## Observe the selected reason before extracting a complete success.
  outcome.status

func value*[T](outcome: AuditRecoveryResult[T]): T {.requires: outcome.status ==
    AuditRecoveryError.None.} =
  ## Source-bearing evidence stays under the exact managed graph lease.
  outcome.completed

func geometryError*[T](outcome: AuditRecoveryResult[
    T]): ErasureLayoutError {.requires: outcome.status == AuditRecoveryError.GeometryFailure.} =
  ## Preserve the actual independent geometry refusal.
  outcome.geometryReason

func reconstructionError*[T](outcome: AuditRecoveryResult[
    T]): ErasureWordError {.requires: outcome.status == AuditRecoveryError.ReconstructionFailure.} =
  ## Arithmetic/local resource refusals do not become authenticated negative evidence.
  outcome.reconstructionReason

func valid*(limits: AuditRecoveryLimits): bool =
  ## Defaults activate no recovery; the protocol-sized domain remains bounded before any product or allocation.
  uint64(limits.bytes) > 0 and uint64(limits.bytes) <= 256'u64*1024*1024 and
    uint64(limits.products) > 0 and uint64(limits.products) <= 16000000000'u64

func valid*(evidence: AuditRecoveryEvidence): bool =
  ## An absent owner cannot authenticate even an empty candidate.
  evidence.data != nil

func matchesOrigin*(evidence: AuditRecoveryEvidence, origin: AuditReportOrigin): bool =
  ## Equal public roots do not substitute another physical private target.
  let data = evidence.data
  data != nil and sameAuditOrigin(data.origin, origin)

func invalidPadding*(evidence: AuditRecoveryEvidence): bool {.requires: evidence.data != nil.} =
  ## True only after actual recovery of independently authenticated unique shards returned nonzero padding.
  let data = evidence.data
  assert data != nil
  data.invalidPadding

proc recoveredBundle*(evidence: AuditRecoveryEvidence): AuditRecoveryResult[seq[byte]] =
  ## Copy only complete valid-length recovered bytes; a certified padding fault has no accepted bundle prefix.
  let data = evidence.data
  if data == nil: return AuditRecoveryResult[seq[byte]](status: AuditRecoveryError.Uninitialized)
  if data.invalidPadding: return AuditRecoveryResult[seq[byte]](
      status: AuditRecoveryError.InvalidPacket)
  result = AuditRecoveryResult[seq[byte]](status: AuditRecoveryError.None, completed: newSeq[byte](data.wire.len))
  for ordinal in 0..<data.wire.len: result.completed[ordinal] = data.wire[ordinal]

func sameSpecifier(left, right: AvailabilitySpecifier): bool =
  ## All six original signed fields matter, including population, package identity and export commitments.
  left.packageHash.bytes == right.packageHash.bytes and
    uint32(left.bundleLength) == uint32(right.bundleLength) and
    left.erasureRoot.bytes == right.erasureRoot.bytes and
    uint16(left.erasureShards) == uint16(right.erasureShards) and
    left.segmentRoot.bytes == right.segmentRoot.bytes and
    uint16(left.segmentCount) == uint16(right.segmentCount)

proc recoverAuditBundle*(origin: AuditReportOrigin,
    packets: openArray[VerifiedAvailabilityTransfer], limits: AuditRecoveryLimits,
    control: AssuranceScanControl = default(AssuranceScanControl)): AuditRecoveryResult[
        AuditRecoveryEvidence] =
  ## Run only on the fixed managed CPU worker with every original source and packet alias frozen through collection or joined close.
  if not limits.valid: return AuditRecoveryResult[AuditRecoveryEvidence](
      status: AuditRecoveryError.InvalidPolicy)
  if not origin.valid: return AuditRecoveryResult[AuditRecoveryEvidence](
      status: AuditRecoveryError.InvalidOrigin)
  if control.stopped: return AuditRecoveryResult[AuditRecoveryEvidence](
      status: AuditRecoveryError.Cancelled)
  let header = origin.originReport.value.ownedReportInfo.value.header
  let expected = AvailabilitySpecifier(packageHash: header.packageHash,
    bundleLength: header.bundleLength,
    erasureRoot: header.erasureRoot, erasureShards: header.erasureShards,
    segmentRoot: header.segmentRoot, segmentCount: header.segmentCount)
  let described = erasureGeometry(expected.bundleLength, expected.erasureShards)
  if described.error != ErasureLayoutError.None:
    return AuditRecoveryResult[AuditRecoveryEvidence](status: AuditRecoveryError.GeometryFailure,
        geometryReason: described.error)
  let geometry = described.value
  if uint64(uint32(expected.bundleLength)) > uint64(MaxBundleBytes) or sizeof(
      VerifiedAvailabilityTransfer) > 128:
    return AuditRecoveryResult[AuditRecoveryEvidence](status: AuditRecoveryError.LimitExceeded)
  if uint64(packets.len) != geometry.originalShards:
    return AuditRecoveryResult[AuditRecoveryEvidence](status: AuditRecoveryError.InvalidCount)
  # MaxBundleBytes plus a stripe is below14MiB; R<=342. Whole scratch products fit uint64 and native indices before allocation.
  let fixed = 3*geometry.paddedBytes+4'u64*1024*1024+geometry.originalShards*128
  if fixed > uint64(limits.bytes) or geometry.paddedBytes > uint64(limits.bytes)-fixed:
    return AuditRecoveryResult[AuditRecoveryEvidence](status: AuditRecoveryError.LimitExceeded)
  var seen = default(array[1023, bool])
  for packet in packets:
    if not packet.valid: return AuditRecoveryResult[AuditRecoveryEvidence](
        status: AuditRecoveryError.InvalidPacket)
    let request = packet.request
    let same = packet.specifier.sameSpecifier(expected)
    let rootMatches = request.root.bytes == expected.erasureRoot.bytes
    let inRange = uint64(request.shard) < uint64(uint16(expected.erasureShards))
    if request.kind != AvailabilityTransferKind.Audit or not same or not rootMatches or not inRange:
      return AuditRecoveryResult[AuditRecoveryEvidence](status: AuditRecoveryError.InvalidPacket)
    let ordinal = int(uint64(request.shard))
    if seen[ordinal]: return AuditRecoveryResult[AuditRecoveryEvidence](
        status: AuditRecoveryError.DuplicateShard)
    seen[ordinal] = true
  var chunks = newSeq[byte](int(geometry.paddedBytes))
  var indices = newSeq[ErasureShardIndex](packets.len)
  for ordinal in 0..<packets.len:
    if control.stopped: return AuditRecoveryResult[AuditRecoveryEvidence](
        status: AuditRecoveryError.Cancelled)
    let packet = packets[ordinal]
    let chunk = packet.bundleShard
    if uint64(chunk.len) != geometry.bundleChunkBytes:
      return AuditRecoveryResult[AuditRecoveryEvidence](status: AuditRecoveryError.InvalidPacket)
    let first = ordinal*chunk.len # R*chunkWidth==paddedBytes was bounded before allocation.
    for position in 0..<chunk.len: chunks[first+position] = chunk[position]
    indices[ordinal] = packet.request.shard
  let recovered = recoverErasureChunks(chunks, indices, expected.bundleLength,
    expected.erasureShards,
    ErasureWordLimits(bytes: ByteLimit(uint64(limits.bytes)-fixed), products: limits.products))
  if control.stopped: return AuditRecoveryResult[AuditRecoveryEvidence](
      status: AuditRecoveryError.Cancelled)
  if recovered.error == ErasureWordError.InvalidPadding:
    return AuditRecoveryResult[AuditRecoveryEvidence](status: AuditRecoveryError.None,
      completed: AuditRecoveryEvidence(data: RecoveryData(origin: origin, invalidPadding: true,
          wire: @[])))
  if recovered.error != ErasureWordError.None:
    return AuditRecoveryResult[AuditRecoveryEvidence](
      status: AuditRecoveryError.ReconstructionFailure,
      reconstructionReason: recovered.error)
  let bytes = recovered.value.recoveredBytes.value
  var wire = newSeq[byte](int(uint32(expected.bundleLength)))
  for ordinal in 0..<wire.len: wire[ordinal] = bytes[ordinal]
  if control.stopped: return AuditRecoveryResult[AuditRecoveryEvidence](
      status: AuditRecoveryError.Cancelled)
  AuditRecoveryResult[AuditRecoveryEvidence](status: AuditRecoveryError.None,
    completed: AuditRecoveryEvidence(data: RecoveryData(origin: origin, invalidPadding: false, wire: wire)))
